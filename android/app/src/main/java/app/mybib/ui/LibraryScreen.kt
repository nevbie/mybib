@file:OptIn(ExperimentalMaterial3Api::class)

package app.mybib.ui

import androidx.compose.foundation.background
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
    fun set(nf: Filters) {
        vm.filters = nf
    }

    @Composable
    fun Chip(label: String, on: Boolean, n: Int? = null, tap: () -> Unit) =
        FilterChip(selected = on, onClick = tap, label = { Text(if (n == null) label else "$label  $n") })

    LazyColumn(state = vm.libraryList, modifier = Modifier.fillMaxSize()) {
        item {
            Text(buildAnnotatedString {
                withStyle(SpanStyle(fontSize = 26.sp, fontWeight = FontWeight.Bold)) { append("mybib ") }
                withStyle(SpanStyle(fontSize = 16.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)) { append("${items.size}") }
            }, modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 4.dp))
        }
        item {
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
        }
        item {
            Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Chip(ui.t("kind.all"), f.kind == "all") { set(f.copy(kind = "all")) }
                for (k in kinds) Chip(ui.t("kind.$k.pl"), f.kind == k) { set(f.copy(kind = if (f.kind == k) "all" else k)) }
            }
        }
        item {
            Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Chip(ui.t("scope.all"), f.scope == "all") { set(f.copy(scope = "all")) }
                for (sc in listOf("wish", "lent", "recommend", "check")) {
                    if (counts.getValue(sc) > 0 || f.scope == sc) Chip(ui.t("scope.$sc"), f.scope == sc, counts[sc]) { set(f.copy(scope = if (f.scope == sc) "all" else sc)) }
                }
                Chip("⚙︎ ${ui.t("lib.more")}", vm.libraryMore || f.extraActive > 0, if (f.extraActive > 0) f.extraActive else null) { vm.libraryMore = !vm.libraryMore }
            }
        }
        if (vm.libraryMore) item { FilterPanel(f) }
        if (items.isEmpty()) {
            item {
                Column(Modifier.fillMaxWidth().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(ui.t("lib.empty"), textAlign = TextAlign.Center)
                    Spacer(Modifier.height(16.dp))
                    Button(onClick = { vm.tab = 1 }) {
                        Icon(Icons.Filled.Add, contentDescription = null)
                        Spacer(Modifier.width(8.dp))
                        Text(ui.t("nav.add"))
                    }
                }
            }
        } else if (sel != null) {
            item {
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
                    IconButton(onClick = { vm.selection = null }) { Icon(Icons.Filled.Close, contentDescription = null) }
                }
            }
        } else {
            item {
                Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 4.dp, top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    Small(if (list.size != items.size) ui.t("lib.shown", "n" to list.size) else "", Modifier.weight(1f))
                    if (list.isNotEmpty()) {
                        TextButton(onClick = { vm.selection = emptySet() }) {
                            Icon(Icons.Filled.DoneAll, contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.width(4.dp))
                            Text(ui.t("sel.start"))
                        }
                    }
                }
            }
        }
        if (items.isNotEmpty() && list.isEmpty()) {
            item { Text(ui.t("lib.noMatch"), textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(32.dp)) }
        }
        items(list, key = { it.id }) { item ->
            ItemTile(
                item = item,
                selected = sel?.contains(item.id),
                onClick = {
                    val s = vm.selection
                    if (s != null) {
                        vm.selection = if (item.id in s) s - item.id else s + item.id
                    } else {
                        vm.push(Screen.Detail(item.id))
                    }
                },
                onLongClick = if (sel == null) {
                    { vm.selection = setOf(item.id) }
                } else null,
            )
        }
    }
    if (bulkEdit) BulkEditSheet(selected) { bulkEdit = false }
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
                    listOf(Opt("all", any)) + statuses.map { Opt(it, ui.t("status.${if (f.kind == "all") "book" else f.kind}.$it")) },
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
            Dropdown(ui.t("lib.sort"), vm.sort, sortKeys.map { Opt(it, ui.t("sort.$it")) }, { vm.sort = it })
            TextButton(onClick = { set(Filters()) }, modifier = Modifier.align(Alignment.End)) { Text(ui.t("lib.reset")) }
        }
    }
}
