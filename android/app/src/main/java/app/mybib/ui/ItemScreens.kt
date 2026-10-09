@file:OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)

package app.mybib.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.mybib.AppViewModel
import app.mybib.Screen
import app.mybib.core.Candidate
import app.mybib.core.Draft
import app.mybib.core.Item
import app.mybib.core.Loan
import app.mybib.core.classifyCode
import app.mybib.core.draftOf
import app.mybib.core.enrichPatch
import app.mybib.core.findDuplicateOf
import app.mybib.core.formats
import app.mybib.core.isFalse
import app.mybib.core.j
import app.mybib.core.kinds
import app.mybib.core.knownPeople
import app.mybib.core.normalizeItem
import app.mybib.core.numberText
import app.mybib.core.statuses
import app.mybib.core.string
import app.mybib.core.strings
import app.mybib.core.today
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonElement

fun shareText(item: Item, ui: Ui): String {
    val lines = mutableListOf(item.title + if (item.creators.isNotEmpty()) " – ${item.creators.joinToString(", ")}" else "")
    if (item.rating > 0) lines += "★".repeat(item.rating) + "☆".repeat(5 - item.rating)
    item.notes?.let { lines += it }
    if (item.recommend) lines += ui.t("share.recommend")
    return lines.joinToString("\n")
}

fun shareUrl(item: Item): String? {
    val isbn = item.isbn ?: return null
    return when (item.kind) {
        "book" -> "https://openlibrary.org/isbn/$isbn"
        "cd" -> "https://musicbrainz.org/search?type=release&query=barcode:$isbn"
        else -> null
    }
}

/** Look an item up online and fill its empty fields with the chosen result. */
fun enrichItem(vm: AppViewModel, item: Item) = vm.push(Screen.Search(item.kind, item.title, item.creators.firstOrNull() ?: "") { c ->
    vm.store.updateItem(item.id, enrichPatch(item.toJson(), c) + draftOf("needsCheck" to false))
})

@Composable
fun ItemScreen(screen: Screen.Detail) {
    val ui = LocalUi.current
    val vm = ui.vm
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val item = ui.byId(screen.id)
    if (item == null) {
        SubScreen("") {}
        return
    }
    val cs = MaterialTheme.colorScheme
    var coverMenu by remember { mutableStateOf(false) }
    var lending by remember { mutableStateOf(false) }
    var moreInfo by remember { mutableStateOf(false) }
    var lendTo by remember { mutableStateOf("") }
    var notes by remember { mutableStateOf(item.notes ?: "") }
    fun up(vararg p: Pair<String, Any?>) = vm.store.updateItem(item.id, *p)
    val loan = item.openLoan
    fun fmtDate(d: String): String {
        val p = d.split("-")
        return if (p.size == 3 && ui.lang == "de") "${p[2].toIntOrNull() ?: p[2]}.${p[1].toIntOrNull() ?: p[1]}.${p[0]}" else d
    }
    val picker = rememberPhotoPicker { uris ->
        scope.launch {
            val data = withContext(Dispatchers.IO) { coverDataUrl(ctx, uris.first()) }
            if (data != null) vm.store.updateItem(screen.id, "coverData" to data)
            coverMenu = false
        }
    }

    val facts = listOf(
        ui.t("field.series") to listOfNotNull(item.series, item.volume).joinToString(" · ").ifEmpty { null },
        ui.t("field.publisher") to item.publisher,
        ui.t("field.year") to item.year?.toString(),
        ui.t("field.pages") to item.pages?.toString(),
        ui.t("field.language") to item.language,
        ui.t("field.isbn") to item.isbn,
        ui.t("field.players") to item.playersMin?.let { min -> "$min" + (item.playersMax?.takeIf { it != min }?.let { "–$it" } ?: "") },
        ui.t("field.playMinutes") to item.playMinutes?.toString(),
        ui.t("field.ageFrom") to item.ageFrom?.let { "$it+" },
        ui.t("field.tags") to item.tags.joinToString(", ").ifEmpty { null },
    ).filter { it.second != null }

    @Composable
    fun H(text: String) = Text(text, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 18.dp, bottom = 6.dp))

    SubScreen(
        "${kindIcon[item.kind]} ${ui.t("kind.${item.kind}")}",
        actions = {
            IconButton(onClick = {
                val url = shareUrl(item)
                shareText(ctx, if (url == null) shareText(item, ui) else "${shareText(item, ui)}\n$url", item.title)
            }) { Icon(Icons.Filled.Share, contentDescription = ui.t("detail.share")) }
            IconButton(onClick = { vm.push(Screen.Form(id = item.id)) }) { Icon(Icons.Filled.Edit, contentDescription = ui.t("detail.edit")) }
            IconButton(onClick = {
                scope.launch {
                    if (vm.dialogs.confirm(ui.t("detail.deleteConfirm", "title" to item.title))) {
                        vm.store.removeItems(listOf(item.id))
                        vm.pop()
                    }
                }
            }) { Icon(Icons.Filled.DeleteOutline, contentDescription = ui.t("detail.delete")) }
        },
    ) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
            Row {
                Box(Modifier.clickable { coverMenu = !coverMenu }.semantics { contentDescription = ui.t("cover.change") }) {
                    CoverImage(item, large = true)
                    Box(
                        Modifier.align(Alignment.BottomEnd).offset(6.dp, 6.dp).size(30.dp).background(cs.surface, CircleShape),
                        contentAlignment = Alignment.Center,
                    ) { Text("📷", fontSize = 14.sp) }
                }
                Spacer(Modifier.width(16.dp))
                Column(Modifier.weight(1f)) {
                    Text(item.title, style = MaterialTheme.typography.titleLarge)
                    item.subtitle?.let { Text(it, color = cs.onSurfaceVariant) }
                    if (item.creators.isNotEmpty()) Text(item.creators.joinToString(", "), fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 4.dp))
                    Spacer(Modifier.height(6.dp))
                    Stars(item.rating, { up("rating" to it) })
                }
            }
            if (coverMenu) {
                FlowRow(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = picker.camera) { IconText(Icons.Filled.PhotoCamera, ui.t("cover.camera")) }
                    OutlinedButton(onClick = picker.gallery) { IconText(Icons.Filled.PhotoLibrary, ui.t("cover.gallery")) }
                    if (item.coverData != null) {
                        TextButton(onClick = {
                            up("coverData" to null)
                            coverMenu = false
                        }) { Text(if (item.coverUrl != null) ui.t("cover.useOnline") else ui.t("form.coverRemove")) }
                    }
                }
            }
            if (item.needsCheck) {
                HintCard(Modifier.padding(top = 14.dp)) {
                    Column {
                        Text(ui.t("detail.needsCheck"), color = Color.Black.copy(alpha = 0.87f))
                        Row {
                            TextButton(onClick = { up("needsCheck" to false) }) { Text("✓ ${ui.t("detail.checked")}") }
                            TextButton(onClick = { enrichItem(vm, item) }) { Text("🔎 ${ui.t("detail.enrich")}") }
                        }
                    }
                }
            }
            H(ui.t("detail.status"))
            Segmented(statuses.map { it to ui.t("status.${item.kind}.$it") }, item.status, { up("status" to it) })
            Spacer(Modifier.height(14.dp))
            CategoryDropdown(item.category ?: "", { up("category" to it.ifEmpty { null }) })
            SwitchRow(ui.t("detail.wishlist"), !item.owned) { up("owned" to !it) }
            SwitchRow("👍 ${ui.t("detail.recommend")}", item.recommend) { up("recommend" to it) }
            if (item.kind == "book") {
                Dropdown(ui.t("field.format"), item.format, formats.map { Opt(it, ui.t("format.$it")) }, { up("format" to it) }, Modifier.fillMaxWidth())
            }
            if (item.owned && item.format == "physical") {
                H(ui.t("detail.place"))
                androidx.compose.runtime.key(item.id) {
                    SuggestField(item.room ?: "", ui.rooms, ui.t("field.room"), { up("room" to it.trim().ifEmpty { null }) })
                }
                H(ui.t("detail.loan"))
                if (loan != null) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(ui.t("detail.lentTo", "name" to loan.to, "date" to fmtDate(loan.since)), Modifier.weight(1f))
                        OutlinedButton(onClick = {
                            up("loans" to item.loans.map { if (it == loan) it.copy(returned = today()) else it })
                        }) { Text("↩ ${ui.t("detail.returned")}") }
                    }
                } else if (lending) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        SuggestField("", knownPeople(ui.items), ui.t("detail.lendWho"), { lendTo = it }, Modifier.weight(1f))
                        Spacer(Modifier.width(8.dp))
                        Button(onClick = {
                            val to = lendTo.trim()
                            if (to.isNotEmpty()) {
                                up("loans" to item.loans + Loan(to, today()))
                                lending = false
                            }
                        }) { Text(ui.t("ok")) }
                    }
                } else {
                    OutlinedButton(onClick = { lending = true }) { Text("↗ ${ui.t("detail.lend")}") }
                }
                for (l in item.loans) {
                    val back = l.returned ?: continue
                    Small(ui.t("detail.loanPast", "name" to l.to, "from" to fmtDate(l.since), "to" to fmtDate(back)))
                }
            }
            H(ui.t("field.notes"))
            OutlinedTextField(
                value = notes,
                onValueChange = {
                    notes = it
                    up("notes" to it)
                },
                placeholder = { Text(ui.t("detail.notesPh")) },
                minLines = 2,
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(14.dp))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(24.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                for ((k, v) in facts) {
                    Column {
                        Text(k, style = MaterialTheme.typography.labelSmall)
                        Text(v ?: "")
                    }
                }
            }
            item.description?.let { d ->
                Spacer(Modifier.height(10.dp))
                Text(d, maxLines = if (moreInfo) Int.MAX_VALUE else 4, overflow = TextOverflow.Ellipsis)
                TextButton(onClick = { moreInfo = !moreInfo }) { Text(if (moreInfo) ui.t("less") else ui.t("more")) }
            }
            if (!item.needsCheck && (!item.hasCover || item.publisher == null)) {
                TextButton(onClick = { enrichItem(vm, item) }) { Text("🔎 ${ui.t("detail.enrich")}") }
            }
            Spacer(Modifier.height(40.dp))
        }
    }
}

@Composable
fun IconText(icon: androidx.compose.ui.graphics.vector.ImageVector, text: String) {
    Icon(icon, contentDescription = null, modifier = Modifier.size(18.dp))
    Spacer(Modifier.width(8.dp))
    Text(text)
}

// ---------- form ----------

private val textFields = listOf("title", "subtitle", "series", "volume", "publisher", "year", "isbn", "language", "pages", "ageFrom", "playersMin", "playersMax", "playMinutes", "room", "notes")

private fun JsonElement?.display() = string ?: numberText ?: ""

private fun splitList(v: String) = v.split(Regex("[,;]")).map { it.trim() }.filter { it.isNotEmpty() }

/** The form's input, kept in the screen entry while the online search is open on top. */
class FormState(initial: Draft) {
    var d by mutableStateOf(initial)
    val text = mutableStateMapOf<String, String>()
    var creators by mutableStateOf("")
    var tags by mutableStateOf("")

    init {
        load(initial)
    }

    fun load(m: Draft) {
        d = m
        for (k in textFields) text[k] = m[k].display()
        creators = m["creators"].strings.joinToString(", ")
        tags = m["tags"].strings.joinToString(", ")
    }

    val kind get() = d["kind"].string ?: "book"
    val title get() = text["title"] ?: ""

    fun set(k: String, v: Any?) {
        d = d + (k to j(v))
    }

    fun full(): Draft = d + textFields.associateWith { k -> j((text[k] ?: "").trim().ifEmpty { null }) } +
        draftOf("creators" to splitList(creators), "tags" to splitList(tags))
}

@Composable
fun ItemForm(screen: Screen.Form) {
    val ui = LocalUi.current
    val vm = ui.vm
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val st = screen.keep("form") {
        val existing = screen.id?.let { vm.store.byId(it) }
        FormState(existing?.toJson() ?: (draftOf("kind" to "book", "format" to "physical", "owned" to true, "status" to "none") +
            (if (ui.settings.lastRoom.isNotEmpty()) draftOf("room" to ui.settings.lastRoom) else emptyMap()) + (screen.draft ?: emptyMap())))
    }
    val kind = st.kind
    val isBook = kind == "book"
    val dup = if (screen.id == null && st.title.isNotBlank()) findDuplicateOf(ui.items, normalizeItem(st.full())) else null
    val picker = rememberPhotoPicker { uris ->
        scope.launch {
            val data = withContext(Dispatchers.IO) { coverDataUrl(ctx, uris.first()) }
            if (data != null) st.set("coverData", data)
        }
    }

    fun fillOnline() = vm.push(Screen.Search(kind, st.title, splitList(st.creators).firstOrNull() ?: "") { c ->
        val cur = st.full()
        val patch = if (st.title.isBlank()) c.data else enrichPatch(cur, c)
        st.load(cur + patch + draftOf("kind" to st.kind, "source" to (if (screen.id != null) st.d["source"] else "search")))
    })

    fun save() {
        val v = st.full().toMutableMap()
        if (v["title"].string.isNullOrEmpty()) return
        v["isbn"].string?.let { raw -> classifyCode(raw)?.let { v["isbn"] = j(it.code) } }
        if (screen.id != null) {
            vm.store.updateItem(screen.id, v)
        } else {
            vm.store.addItems(listOf(v))
            vm.store.updateSettings { it.copy(lastRoom = v["room"].string ?: "") }
        }
        vm.pop()
    }

    @Composable
    fun Field(k: String, label: String, modifier: Modifier = Modifier.fillMaxWidth(), number: Boolean = false, hint: String? = null) = OutlinedTextField(
        value = st.text[k] ?: "",
        onValueChange = { st.text[k] = it },
        label = { Text(label) },
        placeholder = if (hint != null) {
            { Text(hint) }
        } else null,
        singleLine = k != "notes",
        minLines = if (k == "notes") 2 else 1,
        keyboardOptions = KeyboardOptions(keyboardType = if (number) KeyboardType.Number else KeyboardType.Text),
        modifier = modifier,
    )

    @Composable
    fun Two(a: @Composable (Modifier) -> Unit, b: @Composable (Modifier) -> Unit) = Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        a(Modifier.weight(1f))
        b(Modifier.weight(1f))
    }

    SubScreen(if (screen.id != null) ui.t("form.edit") else ui.t("form.new")) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Segmented(kinds.map { it to ui.t("kind.$it") }, kind, { k ->
                st.set("kind", k)
                if (k != "book") st.set("format", "physical")
            })
            Spacer(Modifier.height(4.dp))
            CategoryDropdown(st.d["category"].string ?: "", { st.set("category", it.ifEmpty { null }) })
            Spacer(Modifier.height(8.dp))
            Row {
                CoverImage(st.title.ifEmpty { "?" }, kind, st.d["coverUrl"].string, st.d["coverData"].string, large = true)
                Spacer(Modifier.width(14.dp))
                Column(Modifier.weight(1f)) {
                    OutlinedButton(onClick = picker.camera, Modifier.fillMaxWidth()) { IconText(Icons.Filled.PhotoCamera, ui.t("cover.camera")) }
                    OutlinedButton(onClick = picker.gallery, Modifier.fillMaxWidth()) { IconText(Icons.Filled.PhotoLibrary, ui.t("cover.gallery")) }
                    if (st.d["coverData"].string != null || st.d["coverUrl"].string != null) {
                        // null (not removed) so that saving an existing entry really clears the cover
                        TextButton(onClick = { st.d = st.d + draftOf("coverData" to null, "coverUrl" to null) }, Modifier.fillMaxWidth()) { Text(ui.t("form.coverRemove")) }
                    }
                    OutlinedButton(onClick = { fillOnline() }, Modifier.fillMaxWidth(), enabled = kind != "game") { IconText(Icons.Filled.Search, ui.t("form.fillOnline")) }
                }
            }
            Field("title", "${ui.t("field.title")} *")
            if (dup != null) {
                Text(
                    "⚠︎ ${ui.t("form.duplicate")} ${dup.title}",
                    color = Amber900,
                    modifier = Modifier.clickable { vm.push(Screen.Detail(dup.id)) }.padding(vertical = 4.dp),
                )
            }
            OutlinedTextField(
                st.creators, { st.creators = it },
                label = { Text(ui.t("creator.$kind")) },
                placeholder = { Text(ui.t("form.commaHint")) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            if (isBook) Field("subtitle", ui.t("field.subtitle"))
            Two({ Field("series", ui.t("field.seriesOnly"), it) }, { Field("volume", ui.t("field.volume"), it) })
            Two({ Field("publisher", ui.t(if (kind == "cd") "field.label" else "field.publisher"), it) }, { Field("year", ui.t("field.year"), it, number = true) })
            Two({ Field("isbn", ui.t(if (isBook) "field.isbn" else "field.ean"), it, number = true) }, { Field("language", ui.t("field.language"), it, hint = "de, en, zh …") })
            Two({ if (isBook) Field("pages", ui.t("field.pages"), it, number = true) else Spacer(it) }, { Field("ageFrom", ui.t("field.ageFrom"), it, number = true) })
            if (kind == "game") {
                Two({ Field("playersMin", ui.t("field.playersMin"), it, number = true) }, { Field("playersMax", ui.t("field.playersMax"), it, number = true) })
                Field("playMinutes", ui.t("field.playMinutes"), number = true)
            }
            Spacer(Modifier.height(8.dp))
            if (isBook) Segmented(formats.map { it to ui.t("format.$it") }, st.d["format"].string ?: "physical", { st.set("format", it) })
            Dropdown(ui.t("detail.status"), st.d["status"].string ?: "none", statuses.map { Opt(it, ui.t("status.$kind.$it")) }, { st.set("status", it) }, Modifier.fillMaxWidth())
            val owned = !st.d["owned"].isFalse
            SwitchRow(ui.t("detail.wishlist"), !owned) { st.set("owned", !it) }
            if (owned && (st.d["format"].string ?: "physical") == "physical") {
                SuggestField(st.text["room"] ?: "", ui.rooms, ui.t("field.room"), { st.text["room"] = it })
            }
            OutlinedTextField(
                st.tags, { st.tags = it },
                label = { Text(ui.t("field.tags")) },
                placeholder = { Text(ui.t("form.tagsHint")) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            Field("notes", ui.t("field.notes"))
            Spacer(Modifier.height(14.dp))
            Button(onClick = { save() }, enabled = st.title.isNotBlank(), modifier = Modifier.fillMaxWidth()) { Text(ui.t("save")) }
            Spacer(Modifier.height(30.dp))
        }
    }
}

// ---------- online search ----------

private val searchable = listOf("book", "cd", "dvd")

class SearchState(kind: String, title: String, creator: String) {
    var kind by mutableStateOf(if (kind in searchable) kind else "book")
    var title by mutableStateOf(title)
    var creator by mutableStateOf(creator)
    var busy by mutableStateOf(false)
    var results by mutableStateOf<List<Candidate>?>(null)
    var started = false
}

/** Search Google Books / Open Library / MusicBrainz; the picked result goes to [Screen.Search.onPick]. */
@Composable
fun SearchScreen(screen: Screen.Search) {
    val ui = LocalUi.current
    val vm = ui.vm
    val scope = rememberCoroutineScope()
    val st = screen.keep("search") { SearchState(screen.kind, screen.title, screen.creator) }
    fun run() {
        if (st.title.isBlank() && st.creator.isBlank()) return
        st.busy = true
        st.results = null
        scope.launch {
            try {
                st.results = vm.lookup.searchOnline(st.kind, st.title, st.creator, vm.store.settings.value.googleBooksKey)
            } finally {
                st.busy = false
            }
        }
    }
    LaunchedEffect(Unit) {
        if (!st.started && screen.title.isNotBlank()) run()
        st.started = true
    }
    val search = KeyboardActions(onSearch = { run() })
    SubScreen(ui.t("search.title")) {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp)) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Segmented(searchable.map { it to ui.t("kind.$it") }, st.kind, { st.kind = it })
                    OutlinedTextField(
                        st.title, { st.title = it }, label = { Text(ui.t("field.title")) }, singleLine = true,
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search), keyboardActions = search, modifier = Modifier.fillMaxWidth(),
                    )
                    OutlinedTextField(
                        st.creator, { st.creator = it }, label = { Text(ui.t("creator.${st.kind}")) }, singleLine = true,
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search), keyboardActions = search, modifier = Modifier.fillMaxWidth(),
                    )
                    Spacer(Modifier.height(4.dp))
                    Button(onClick = { run() }, enabled = !st.busy, modifier = Modifier.fillMaxWidth()) {
                        IconText(Icons.Filled.Search, if (st.busy) ui.t("search.busy") else ui.t("search.go"))
                    }
                    if (st.busy) Box(Modifier.fillMaxWidth().padding(20.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                    if (st.results?.isEmpty() == true) Text(ui.t("search.none"), Modifier.padding(16.dp))
                }
            }
            items(st.results ?: emptyList()) { c ->
                Row(
                    Modifier.fillMaxWidth().clickable {
                        vm.pop()
                        screen.onPick(c)
                    }.padding(vertical = 8.dp),
                ) {
                    CoverImage(c.title, c.kind, c.coverUrl)
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(c.title, fontWeight = FontWeight.SemiBold)
                        c.data["subtitle"].string?.let { Text(it) }
                        Text(c.creators.joinToString(", "))
                        Small(listOfNotNull(c.data["publisher"].display().ifEmpty { null }, c.data["year"].display().ifEmpty { null }, c.data["language"].display().ifEmpty { null }, c.via).joinToString(" · "))
                    }
                }
            }
        }
    }
}
