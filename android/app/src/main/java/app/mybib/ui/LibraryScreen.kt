@file:OptIn(ExperimentalMaterial3Api::class, androidx.compose.foundation.ExperimentalFoundationApi::class)

package app.mybib.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.Image
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.requiredWidth
import androidx.compose.foundation.layout.widthIn
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import app.mybib.core.Item
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items as gridItems
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Reorder
import androidx.compose.material.icons.filled.ViewColumn
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.SmallFloatingActionButton
import app.mybib.core.allLanguages
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DoneAll
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.MergeType
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.mybib.Screen
import app.mybib.core.Filters
import app.mybib.core.applyFilters
import app.mybib.core.formats
import app.mybib.core.kinds
import app.mybib.core.sortItems
import app.mybib.core.sortKeys
import app.mybib.core.statuses
import kotlinx.coroutines.launch

@Composable
fun LibraryScreen() {
    val ui = LocalUi.current
    val vm = ui.vm
    val f = vm.filters
    val items = ui.items
    val list = remember(items, f, vm.sort) { sortItems(applyFilters(items, f), vm.sort) }
    val counts = mapOf(
        "wish" to items.count { !it.owned },
        "lent" to items.count { it.openLoan != null },
        "recommend" to items.count { it.recommend },
        "check" to items.count { it.needsCheck },
    )
    val sel = vm.selection
    val selected = if (sel == null) emptyList() else list.filter { it.id in sel }.map { it.id }
    var bulkEdit by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val grid = vm.view == "grid"

    // merge the selected entries into one, choosing which cover, author … to keep
    fun merge() {
        vm.push(Screen.Merge(selected))
        vm.selection = null
    }
    fun set(nf: Filters) {
        vm.filters = nf
    }
    fun open(id: String) {
        val s = vm.selection
        if (s != null) vm.selection = if (id in s) s - id else s + id else vm.push(Screen.Detail(id))
    }
    // a long press starts the selection (or adds to it) – also far down the list
    fun longPress(id: String) {
        vm.selection = (vm.selection ?: emptySet()) + id
    }

    @Composable
    fun Chip(label: String, on: Boolean, n: Int? = null, tap: () -> Unit) =
        FilterChip(selected = on, onClick = tap, label = { Text(if (n == null) label else "$label  $n") })

    @Composable
    fun Header() {
        Column {
            Text(buildAnnotatedString {
                withStyle(SpanStyle(fontSize = 26.sp, fontWeight = FontWeight.Bold)) { append("mybib ") }
                withStyle(SpanStyle(fontSize = 16.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)) { append("${items.size}") }
            }, modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 4.dp))
            OutlinedTextField(
                value = f.q,
                onValueChange = { set(vm.filters.copy(q = it)) },
                placeholder = { Text(ui.t("lib.search")) },
                leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                trailingIcon = if (f.q.isEmpty()) null else {
                    { IconButton(onClick = { set(vm.filters.copy(q = "")) }) { Icon(Icons.Filled.Clear, contentDescription = null) } }
                },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp),
            )
            Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Chip(ui.t("kind.all"), f.kind == "all") { set(f.copy(kind = "all")) }
                for (k in kinds.flatMap { if (it == "book") listOf("book", "ebook") else listOf(it) }) {
                    Chip(if (k == "ebook") ui.t("lib.ebooks") else ui.t("kind.$k.pl"), f.kind == k) { set(f.copy(kind = if (f.kind == k) "all" else k)) }
                }
            }
            Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Chip(ui.t("scope.all"), f.scope == "all") { set(f.copy(scope = "all")) }
                for (sc in listOf("wish", "lent", "recommend", "check")) {
                    if (counts.getValue(sc) > 0 || f.scope == sc) Chip(ui.t("scope.$sc"), f.scope == sc, counts[sc]) { set(f.copy(scope = if (f.scope == sc) "all" else sc)) }
                }
                Chip("⚙︎ ${ui.t("lib.more")}", vm.libraryMore || f.extraActive > 0, if (f.extraActive > 0) f.extraActive else null) { vm.libraryMore = !vm.libraryMore }
            }
            if (vm.libraryMore) FilterPanel(f)
            if (items.isEmpty()) {
                Column(Modifier.fillMaxWidth().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(ui.t("lib.empty"), textAlign = TextAlign.Center)
                    Spacer(Modifier.height(16.dp))
                    Button(onClick = { vm.tab = 1 }) {
                        Icon(Icons.Filled.Add, contentDescription = null)
                        Spacer(Modifier.width(8.dp))
                        Text(ui.t("nav.add"))
                    }
                }
            } else if (sel == null) {
                Toolbar(list.size, items.size)
            }
            if (items.isNotEmpty() && list.isEmpty()) {
                Text(ui.t("lib.noMatch"), textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(32.dp))
            }
        }
    }

    val scrolledFar = if (grid) vm.libraryGrid.firstVisibleItemIndex > 12 else vm.libraryList.firstVisibleItemIndex > 8

    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize()) {
            // the selection bar stays on screen however far down the list you are
            if (sel != null) {
                Row(
                    Modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, top = 8.dp, bottom = 4.dp)
                        .background(MaterialTheme.colorScheme.primaryContainer, RoundedCornerShape(12.dp)).padding(start = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(ui.t("sel.count", "n" to selected.size), fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                    TextButton(onClick = { vm.selection = if (selected.size == list.size) emptySet() else list.map { it.id }.toSet() }) {
                        Text(if (selected.size == list.size) ui.t("ai.none") else ui.t("sel.all", "n" to list.size))
                    }
                    Button(onClick = { bulkEdit = true }, enabled = selected.isNotEmpty()) {
                        Icon(Icons.Filled.Edit, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(4.dp))
                        Text(ui.t("sel.edit"))
                    }
                    IconButton(onClick = { merge() }, enabled = selected.size > 1) {
                        Icon(Icons.Filled.MergeType, contentDescription = ui.t("sel.merge"))
                    }
                    IconButton(onClick = { vm.selection = null }) { Icon(Icons.Filled.Close, contentDescription = null) }
                }
            }
            if (grid) {
                LazyVerticalGrid(
                    columns = GridCells.Adaptive(104.dp),
                    state = vm.libraryGrid,
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(start = 8.dp, end = 8.dp, bottom = 80.dp),
                ) {
                    item(span = { GridItemSpan(maxLineSpan) }) { Header() }
                    gridItems(list, key = { it.id }) { item ->
                        GridTile(item, onClick = { open(item.id) }, selected = sel?.contains(item.id), onLongClick = { longPress(item.id) })
                    }
                }
            } else {
                LazyColumn(state = vm.libraryList, modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 80.dp)) {
                    item { Header() }
                    if (vm.view == "shelf") {
                        // shelf view: the spines side by side, one shelf per room
                        val rooms = list.groupBy { it.room ?: "" }.entries.toList()
                        items(rooms, key = { "room:" + it.key }) { (room, group) ->
                            Shelf(room.ifEmpty { ui.t("places.none") }, group, sel, { open(it) }, { longPress(it) })
                        }
                        return@LazyColumn
                    }
                    items(list, key = { it.id }) { item ->
                        ItemTile(
                            item = item,
                            selected = sel?.contains(item.id),
                            onClick = { open(item.id) },
                            onLongClick = { longPress(item.id) },
                            compact = vm.view == "compact",
                        )
                    }
                }
            }
        }
        if (scrolledFar) {
            SmallFloatingActionButton(
                onClick = { scope.launch { if (grid) vm.libraryGrid.animateScrollToItem(0) else vm.libraryList.animateScrollToItem(0) } },
                modifier = Modifier.align(Alignment.BottomEnd).padding(16.dp),
            ) { Icon(Icons.Filled.KeyboardArrowUp, contentDescription = ui.t("lib.top")) }
        }
    }
    if (bulkEdit) BulkEditSheet(selected) { bulkEdit = false }
}

/** Number of matches, sort, view mode and "Select" – above the list. */
@Composable
private fun Toolbar(shown: Int, total: Int) {
    val ui = LocalUi.current
    val vm = ui.vm
    var sortMenu by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 4.dp, top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Small(if (shown != total) ui.t("lib.shown", "n" to shown) else "", Modifier.weight(1f))
        Box {
            TextButton(onClick = { sortMenu = true }) { Text("↕ ${ui.t("sort.${vm.sort}")}", maxLines = 1) }
            DropdownMenu(expanded = sortMenu, onDismissRequest = { sortMenu = false }) {
                for (k in sortKeys) {
                    DropdownMenuItem(text = { Text(ui.t("sort.$k")) }, onClick = {
                        vm.sort = k
                        sortMenu = false
                    })
                }
            }
        }
        for ((v, icon) in listOf("list" to Icons.AutoMirrored.Filled.List, "compact" to Icons.Filled.Reorder, "grid" to Icons.Filled.GridView, "shelf" to Icons.Filled.ViewColumn)) {
            IconButton(onClick = { vm.view = v }, modifier = Modifier.size(36.dp)) {
                Icon(icon, contentDescription = ui.t("lib.view.$v"), tint = if (vm.view == v) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        if (shown > 0) {
            TextButton(onClick = { vm.selection = emptySet() }) {
                Icon(Icons.Filled.DoneAll, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(4.dp))
                Text(ui.t("sel.start"))
            }
        }
    }
}

@Composable
private fun FilterPanel(f: Filters) {
    val ui = LocalUi.current
    val vm = ui.vm
    fun set(nf: Filters) {
        vm.filters = nf
    }
    val any = ui.t("any")
    val rooms = ui.rooms
    Card(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 4.dp)) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Dropdown(
                    ui.t("lib.status"), f.status,
                    listOf(Opt("all", any)) + statuses.map { Opt(it, ui.t("status.${if (f.kind == "all" || f.kind == "ebook") "book" else f.kind}.$it")) },
                    { set(f.copy(status = it)) }, Modifier.weight(1f),
                )
                Dropdown(ui.t("field.format"), f.format, listOf(Opt("all", any)) + formats.map { Opt(it, ui.t("format.$it")) }, { set(f.copy(format = it)) }, Modifier.weight(1f))
            }
            CategoryDropdown(f.category, { set(f.copy(category = it)) }, extra = listOf(Opt("all", any)))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                val room = if (f.room in rooms || f.room == "all" || f.room == "") f.room else "all"
                Dropdown(
                    ui.t("field.room"), room,
                    listOf(Opt("all", any)) + rooms.map { Opt(it, it) } + Opt("", ui.t("places.none")),
                    { set(f.copy(room = it)) }, Modifier.weight(1f),
                )
                Dropdown(ui.t("lib.minRating"), f.minRating, listOf(Opt(0, any)) + (1..5).map { Opt(it, "★".repeat(it)) }, { set(f.copy(minRating = it)) }, Modifier.weight(1f))
            }
            val languages = remember(ui.items) { allLanguages(ui.items) }
            if (languages.isNotEmpty()) {
                Dropdown(
                    ui.t("lib.language"), f.language,
                    listOf(Opt("all", any)) + languages.map { Opt(it, it) } + Opt("", ui.t("lib.noLanguage")),
                    { set(f.copy(language = it)) },
                )
            }
            TextButton(onClick = { set(Filters()) }, modifier = Modifier.align(Alignment.End)) { Text(ui.t("lib.reset")) }
        }
    }
}

/** One room as a shelf: the spines side by side – the own spine photo, else a coloured strip with the title. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Shelf(room: String, group: List<Item>, sel: Set<String>?, onClick: (String) -> Unit, onLongClick: (String) -> Unit) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
        Text(room, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(6.dp))
        FlowRow(
            Modifier.fillMaxWidth().drawBehind {
                // the shelf board under each row of spines
                drawRect(Color(0xFFA47551), topLeft = androidx.compose.ui.geometry.Offset(0f, size.height - 8.dp.toPx()), size = androidx.compose.ui.geometry.Size(size.width, 8.dp.toPx()))
            }.padding(bottom = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(2.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            for (i in group) Spine(i, sel?.contains(i.id), { onClick(i.id) }, { onLongClick(i.id) })
        }
    }
}

@Composable
private fun Spine(item: Item, selected: Boolean?, onClick: () -> Unit, onLongClick: () -> Unit) {
    val bmp = remember(item.spineData) { coverBitmap(item.spineData) }
    val hue = remember(item.title) { item.title.fold(0) { h, c -> (h * 31 + c.code) % 360 } }
    val border = if (selected == true) Modifier.border(3.dp, MaterialTheme.colorScheme.primary, RoundedCornerShape(2.dp)) else Modifier
    val m = Modifier.height(150.dp).then(border).combinedClickable(onClick = onClick, onLongClick = onLongClick)
    if (bmp != null) {
        Image(bmp, contentDescription = item.title, contentScale = ContentScale.FillHeight, modifier = m.widthIn(min = 14.dp, max = 70.dp).clip(RoundedCornerShape(2.dp)))
    } else {
        Box(
            m.width(28.dp).clip(RoundedCornerShape(2.dp)).background(Color.hsl(hue.toFloat(), 0.4f, 0.45f)),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                item.title,
                color = Color.White,
                fontSize = 11.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.requiredWidth(140.dp).rotate(-90f),
            )
        }
    }
}
