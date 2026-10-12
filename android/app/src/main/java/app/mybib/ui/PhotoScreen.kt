@file:OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)

package app.mybib.ui

import android.net.Uri
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewModelScope
import app.mybib.Screen
import app.mybib.core.Draft
import app.mybib.core.findMatchOf
import app.mybib.core.completionPatch
import app.mybib.core.Item
import app.mybib.core.RecognizeError
import app.mybib.core.Recognized
import app.mybib.core.draftOf
import app.mybib.core.enrichPatch
import app.mybib.core.findDuplicateOf
import app.mybib.core.kinds
import app.mybib.core.matchScore
import app.mybib.core.normalizeItem
import app.mybib.core.string
import app.mybib.core.strings
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** One recognised item in the review list. */
class PhotoRow(
    val base: Draft,
    val confidence: String,
    val remark: String,
    selected: Boolean,
    val dupTitle: String?,
    /** existing entry this cover probably belongs to (cover mode) */
    val target: Item? = null,
) {
    /** complete [target] instead of adding a new entry */
    var update by mutableStateOf(target != null)
    var title by mutableStateOf(base["title"].string ?: "")
    var creators by mutableStateOf(base["creators"].strings.joinToString(", "))
    var kind by mutableStateOf(base["kind"].string ?: "book")
    var selected by mutableStateOf(selected)

    fun draft(): Draft = base + draftOf("title" to title, "creators" to creators.split(",").map { it.trim() }.filter { it.isNotEmpty() }, "kind" to kind)
}

class PhotoState {
    var hint by mutableStateOf("")
    val rows = mutableStateListOf<PhotoRow>()
    var status by mutableStateOf("")
    var busy by mutableStateOf(false)
    var enrich by mutableStateOf(true)
    var room by mutableStateOf<String?>(null)
}

/**
 * Add by photo.
 * - shelf: one or more shelf photos → Claude reads all spines → review list → add.
 * - cover: one or many front covers (one item per photo) → (with key) titles recognised → review list → add;
 *   each photo becomes that entry's cover.
 */
@Composable
fun PhotoScreen(screen: Screen.Photo) {
    val ui = LocalUi.current
    val vm = ui.vm
    val ctx = LocalContext.current.applicationContext
    val st = screen.keep("photo") { PhotoState() }
    val shelf = screen.mode == "shelf"
    val hasKey = ui.settings.claudeKey.isNotEmpty()
    // an entry needs a title – without a key it is typed into the list
    val selected = st.rows.count { it.selected && it.title.isNotBlank() }
    val room = st.room ?: ui.settings.lastRoom

    fun err(e: Exception) =
        if (e is RecognizeError) ui.t("ai.err.${e.code}") + (if (e.code == "other" || e.code == "parse") " (${e.message})" else "") else e.toString()

    suspend fun recognize(jpeg: ByteArray): List<Recognized> {
        val s = vm.store.settings.value
        return vm.claude.recognizePhoto(s.claudeKey, s.claudeModel, jpeg, st.hint)
    }

    suspend fun readShelf(photos: List<Uri>) {
        st.busy = true
        vm.keepScreenOn = true
        for ((n, uri) in photos.withIndex()) {
            st.status = ui.t("ai.reading", "i" to n + 1, "n" to photos.size)
            try {
                val jpeg = withContext(Dispatchers.IO) { loadJpeg(ctx, uri, 2400, 88) } ?: continue
                for (f in recognize(jpeg)) {
                    val draft = f.toDraft()
                    val dup = findDuplicateOf(vm.store.items.value, normalizeItem(draft))?.title
                        ?: st.rows.firstOrNull { it.title == f.title && it.base["volume"] == draft["volume"] }?.title
                    st.rows.add(PhotoRow(draft, f.confidence, f.remark, dup == null, dup))
                }
            } catch (e: Exception) {
                if (e is CancellationException) throw e
                vm.dialogs.info(err(e))
                if (e is RecognizeError && e.code == "auth") break
            }
        }
        st.busy = false
        vm.keepScreenOn = false
        st.status = ""
    }

    /**
     * Cover photos: with a key Claude reads every cover on a photo (one or several) and each is cut out as its
     * own cover; without a key one photo = one entry. Recognised items that are already in the catalogue are
     * offered as "complete the existing entry" (cover photo + empty fields) instead of a new one.
     */
    suspend fun readCovers(photos: List<Uri>) {
        st.busy = true
        vm.keepScreenOn = true
        for ((n, uri) in photos.withIndex()) {
            st.status = ui.t("ai.readingCovers", "i" to n + 1, "n" to photos.size)
            // large enough to read several titles on one photo and to cut covers out of it
            val jpeg = withContext(Dispatchers.IO) { loadJpeg(ctx, uri, 2000, 85) } ?: continue
            val whole = withContext(Dispatchers.IO) { coverDataUrl(ctx, uri) } ?: continue
            val found = mutableListOf<PhotoRow>()
            if (vm.store.settings.value.claudeKey.isNotEmpty()) {
                try {
                    val recognized = recognize(jpeg)
                    for (f in recognized) {
                        val box = f.box
                        // several covers: cut each one out; turned upright either way
                        val cut = if (recognized.size > 1 && box != null) withContext(Dispatchers.Default) { cropCover(jpeg, box, f.rotation) } else null
                        val cover = cut ?: withContext(Dispatchers.Default) { rotateDataUrl(whole, f.rotation) }
                        val draft = f.toDraft() + draftOf("coverData" to cover)
                        found += PhotoRow(draft, f.confidence, f.remark, true, null, findMatchOf(vm.store.items.value, draft))
                    }
                } catch (e: Exception) {
                    if (e is CancellationException) throw e
                    vm.dialogs.info(err(e))
                    if (e is RecognizeError && e.code == "auth") break
                }
            }
            if (found.isEmpty()) found += PhotoRow(draftOf("title" to "", "kind" to "book", "coverData" to whole, "source" to "manual"), "high", "", true, null)
            for (row in found) {
                // the same book twice in this batch (e.g. photographed twice)
                val twice = if (row.title.isEmpty()) null else st.rows.firstOrNull { it.title == row.title && it.base["volume"] == row.base["volume"] }?.title
                if (twice != null) {
                    st.rows.add(PhotoRow(row.base, row.confidence, row.remark, false, twice, row.target))
                } else {
                    st.rows.add(row)
                }
            }
        }
        st.busy = false
        vm.keepScreenOn = false
        st.status = ""
    }

    val picker = rememberPhotoPicker(multiple = true) { uris ->
        // the view model scope: reading goes on when the app is left or the screen turns
        vm.viewModelScope.launch { if (shelf) readShelf(uris) else readCovers(uris) }
    }

    fun addAll() = vm.viewModelScope.launch {
        val sel = st.rows.filter { it.selected && it.title.isNotBlank() }
        val r0 = room
        st.busy = true
        vm.keepScreenOn = true
        val drafts = mutableListOf<Draft>()
        var completed = 0
        for ((n, row) in sel.withIndex()) {
            var d = row.draft() + draftOf("room" to r0.ifEmpty { null })
            val kind = row.kind
            if (st.enrich && (kind == "book" || kind == "cd")) {
                st.status = ui.t("ai.enrichingN", "i" to n + 1, "n" to sel.size)
                val title = row.title
                val creators = d["creators"].strings
                val found = try {
                    vm.lookup.searchOnline(kind, title, creators.firstOrNull() ?: "", vm.store.settings.value.googleBooksKey)
                } catch (e: Exception) {
                    if (e is CancellationException) throw e
                    emptyList()
                }
                val best = found.firstOrNull { matchScore(title, creators, it) >= 0.75 }
                // keep the title as printed on the spine, only fill gaps; an own cover photo stays the cover
                if (best != null) d = (d + enrichPatch(d, best)).let { if (it["coverData"].string != null) it - "coverUrl" else it }
                // MusicBrainz asks for max. 1 request per second
                if (kind == "cd") delay(1000)
            }
            val old = if (row.update) row.target?.let { t -> vm.store.byId(t.id) } else null
            if (old != null) {
                // complete the existing entry; its room and personal data stay as they are
                val patch = completionPatch(old, d)
                if (patch.isNotEmpty()) vm.store.updateItem(old.id, patch)
                completed++
            } else {
                drafts += d
            }
        }
        if (drafts.isNotEmpty()) vm.store.addItems(drafts)
        vm.store.updateSettings { it.copy(lastRoom = r0) }
        st.busy = false
        vm.keepScreenOn = false
        st.status = ""
        vm.dialogs.info(if (completed > 0) ui.t("ai.addedCompleted", "n" to drafts.size, "m" to completed) else ui.t("ai.added", "n" to drafts.size))
        vm.pop()
    }

    SubScreen(
        if (shelf) ui.t("add.shelf") else ui.t("add.cover"),
        bottomBar = {
            if (st.rows.isNotEmpty()) {
                Button(
                    onClick = { addAll() },
                    enabled = !st.busy && selected > 0,
                    modifier = Modifier.fillMaxWidth().navigationBarsPadding().padding(12.dp),
                ) { Text(if (st.rows.any { it.selected && it.update && it.target != null }) ui.t("ai.applyN", "n" to selected) else ui.t("ai.addN", "n" to selected)) }
            }
        },
    ) {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (shelf && !hasKey) HintCard { Text(ui.t("ai.noKey"), color = androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.87f)) }
                    if (!shelf) Small(if (hasKey) ui.t("ai.coverHint") else ui.t("ai.coverNoKey"))
                    if (!shelf) Small(ui.t("ai.coversMany"))
                    if (shelf && hasKey) Small(ui.t("ai.shelfHint"))
                    SuggestField(room, ui.rooms, ui.t("field.room"), { st.room = it.trim() })
                    if (hasKey) {
                        OutlinedTextField(st.hint, { st.hint = it }, label = { Text(ui.t("ai.hintPh")) }, singleLine = true, modifier = Modifier.fillMaxWidth())
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        val enabled = !st.busy && !(shelf && !hasKey)
                        Button(onClick = picker.camera, enabled = enabled, modifier = Modifier.weight(1f)) { IconText(Icons.Filled.PhotoCamera, ui.t("ai.camera")) }
                        OutlinedButton(onClick = picker.gallery, enabled = enabled, modifier = Modifier.weight(1f)) { IconText(Icons.Filled.PhotoLibrary, ui.t("ai.gallery")) }
                    }
                    if (st.status.isNotEmpty()) {
                        Row(Modifier.padding(vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                            CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                            Spacer(Modifier.width(12.dp))
                            Text(st.status, Modifier.weight(1f))
                        }
                    }
                    if (st.rows.isNotEmpty()) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(if (shelf) ui.t("ai.found", "n" to st.rows.size) else ui.t("ai.photosN", "n" to st.rows.size), fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                            TextButton(onClick = {
                                val all = selected == 0
                                st.rows.forEach { it.selected = all }
                            }) { Text(if (selected > 0) ui.t("ai.none") else ui.t("ai.all")) }
                        }
                        SwitchRow(ui.t("ai.enrich"), st.enrich) { st.enrich = it }
                    }
                }
            }
            items(st.rows) { r -> RowCard(r) }
        }
    }
}

@Composable
private fun RowCard(r: PhotoRow) {
    val ui = LocalUi.current
    val cs = MaterialTheme.colorScheme
    var kindMenu by remember { mutableStateOf(false) }
    Card(Modifier.fillMaxWidth().alpha(if (r.selected) 1f else 0.5f)) {
        Row(Modifier.padding(start = 4.dp, top = 4.dp, end = 12.dp, bottom = 8.dp)) {
            Checkbox(checked = r.selected, onCheckedChange = { r.selected = it })
            coverBitmap(r.base["coverData"].string)?.let {
                Image(it, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.padding(top = 10.dp, end = 10.dp).size(44.dp, 64.dp).clip(RoundedCornerShape(4.dp)))
            }
            Column(Modifier.weight(1f).padding(top = 12.dp)) {
                BasicTextField(
                    r.title, { r.title = it },
                    textStyle = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold, color = cs.onSurface),
                    cursorBrush = SolidColor(cs.primary),
                    modifier = Modifier.fillMaxWidth(),
                    decorationBox = { inner ->
                        if (r.title.isEmpty()) Text("${ui.t("field.title")} *", style = MaterialTheme.typography.bodyLarge, color = cs.onSurfaceVariant)
                        inner()
                    },
                )
                BasicTextField(
                    r.creators, { r.creators = it },
                    textStyle = MaterialTheme.typography.bodyMedium.copy(color = cs.onSurface),
                    cursorBrush = SolidColor(cs.primary),
                    modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
                    decorationBox = { inner ->
                        if (r.creators.isEmpty()) Text(ui.t("creator.${r.kind}"), style = MaterialTheme.typography.bodyMedium, color = cs.onSurfaceVariant)
                        inner()
                    },
                )
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    androidx.compose.foundation.layout.Box {
                        TextButton(onClick = { kindMenu = true }) { Text("${kindIcon[r.kind]} ${ui.t("kind.${r.kind}")} ▾") }
                        DropdownMenu(expanded = kindMenu, onDismissRequest = { kindMenu = false }) {
                            for (k in kinds) {
                                DropdownMenuItem(text = { Text("${kindIcon[k]} ${ui.t("kind.$k")}") }, onClick = {
                                    r.kind = k
                                    kindMenu = false
                                })
                            }
                        }
                    }
                    val sv = listOfNotNull(r.base["series"].string, r.base["volume"].string).joinToString(" ")
                    if (sv.isNotEmpty()) Text(sv, Modifier.align(Alignment.CenterVertically))
                    if (r.confidence != "high") Pill(ui.t("ai.conf.${r.confidence}"), Amber200)
                    if (r.dupTitle != null) Pill(ui.t("ai.dup"), Pink100)
                }
                r.target?.let { t ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(checked = r.update, onCheckedChange = { r.update = it })
                        Text(ui.t("ai.completeExisting", "title" to t.title), style = MaterialTheme.typography.bodySmall)
                    }
                }
                if (r.remark.isNotEmpty()) Small(r.remark)
            }
        }
    }
}
