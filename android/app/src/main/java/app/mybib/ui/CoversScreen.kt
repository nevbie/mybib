package app.mybib.ui

import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.mybib.Screen
import app.mybib.core.sortItems
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Kept with the screen, so the list and room survive the camera and gallery round trips. */
class CoversState {
    var room by mutableStateOf("all")
    var list by mutableStateOf<List<String>?>(null)
    var target by mutableStateOf<String?>(null)
    var busy by mutableStateOf("")
}

/**
 * Add cover photos to existing entries: one at a time (camera / gallery per row), or many photos
 * at once, handed out in list order to the entries that still have no cover.
 * Without [Screen.Covers.ids] the list holds all entries without a cover, in shelf order.
 */
@Composable
fun CoversScreen(screen: Screen.Covers) {
    val ui = LocalUi.current
    val vm = ui.vm
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val st = screen.keep("covers") { CoversState() }

    // the list is fixed when the screen opens (and when the room changes), so entries don't vanish once they got a cover
    fun build(): List<String> {
        val base = screen.ids?.mapNotNull { ui.byId(it) } ?: ui.items.filter { it.coverData == null && it.coverUrl == null }
        return sortItems(base.filter { st.room == "all" || (it.room ?: "") == st.room }, "place").map { it.id }
    }
    val list = st.list ?: build().also { st.list = it }
    val live = list.mapNotNull { ui.byId(it) }
    val missing = live.filter { it.coverData == null }

    suspend fun save(id: String, uri: Uri) {
        val data = withContext(Dispatchers.IO) { coverDataUrl(ctx, uri) } ?: return
        vm.store.updateItem(id, "coverData" to data)
    }

    val one = rememberPhotoPicker { uris ->
        val id = st.target ?: return@rememberPhotoPicker
        scope.launch {
            st.busy = ui.t("covers.saving")
            save(id, uris.first())
            st.busy = ""
        }
    }
    val many = rememberPhotoPicker(multiple = true) { uris ->
        scope.launch {
            val targets = missing.take(uris.size)
            if (targets.isEmpty()) return@launch
            val extra = if (uris.size > targets.size) " " + ui.t("covers.manyExtra", "n" to uris.size - targets.size) else ""
            if (!vm.dialogs.confirm(ui.t("covers.manyConfirm", "n" to targets.size, "first" to targets.first().title) + extra)) return@launch
            for ((n, item) in targets.withIndex()) {
                st.busy = ui.t("covers.savingN", "i" to n + 1, "n" to targets.size)
                save(item.id, uris[n])
            }
            st.busy = ""
        }
    }

    SubScreen("📷 ${ui.t("covers.title")}") {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Small(ui.t("covers.intro"))
                    if (screen.ids == null) {
                        Dropdown(
                            ui.t("field.room"), st.room,
                            listOf(Opt("all", ui.t("any"))) + ui.rooms.map { Opt(it, it) } + Opt("", ui.t("places.none")),
                            {
                                st.room = it
                                st.list = null
                            },
                        )
                    }
                    Text(ui.t("covers.left", "n" to missing.size, "total" to live.size), fontWeight = FontWeight.Bold)
                    Button(onClick = many.gallery, enabled = missing.isNotEmpty() && st.busy.isEmpty(), modifier = Modifier.fillMaxWidth()) {
                        Text("🖼 ${ui.t("covers.many")}")
                    }
                    Small(ui.t("covers.manyHint"))
                    if (st.busy.isNotEmpty()) {
                        Row(Modifier.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                            CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                            Spacer(Modifier.width(12.dp))
                            Text(st.busy)
                        }
                    }
                    if (live.isEmpty()) Small(ui.t("covers.none"))
                }
            }
            items(live, key = { it.id }) { i ->
                Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    CoverImage(i)
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(listOfNotNull(i.title, i.volume).joinToString(" · "), fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        if (i.creators.isNotEmpty()) Text(i.creators.joinToString(", "), style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        i.room?.let { Small(it) }
                    }
                    if (i.coverData != null) Icon(Icons.Filled.Check, contentDescription = ui.t("covers.done"), tint = MaterialTheme.colorScheme.primary)
                    IconButton(onClick = {
                        st.target = i.id
                        one.camera()
                    }, enabled = st.busy.isEmpty()) { Icon(Icons.Filled.PhotoCamera, contentDescription = ui.t("cover.camera")) }
                    IconButton(onClick = {
                        st.target = i.id
                        one.gallery()
                    }, enabled = st.busy.isEmpty()) { Icon(Icons.Filled.PhotoLibrary, contentDescription = ui.t("cover.gallery")) }
                }
                HorizontalDivider()
            }
        }
    }
}
