package app.mybib.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.mybib.Screen
import app.mybib.core.Filters
import app.mybib.core.Item
import app.mybib.core.applyFilters
import app.mybib.core.duplicateGroups
import app.mybib.core.groupKey
import app.mybib.core.kinds
import app.mybib.core.mergeGroup
import app.mybib.core.similarGroups
import app.mybib.core.statuses
import kotlinx.coroutines.launch

private val scopes = listOf("all", "owned", "wish", "lent", "recommend", "check")

/** Tidy up: find and merge duplicates, edit or delete many entries chosen by filter. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun TidyScreen(screen: Screen.Tidy) {
    val ui = LocalUi.current
    val vm = ui.vm
    val scope = rememberCoroutineScope()
    val groups = remember(ui.items, ui.settings.dupIgnore) { duplicateGroups(ui.items, ui.settings.dupIgnore) }
    // same title, but author/volume/format differ – maybe the same thing, maybe not: merged only by hand
    val similar = remember(ui.items, ui.settings.dupIgnore, groups) {
        similarGroups(ui.items, ui.settings.dupIgnore, groups.flatten().map { it.id }.toSet())
    }
    var showSimilar by remember { mutableStateOf(false) }

    fun mergeAll() = scope.launch {
        val merges = groups.map(::mergeGroup)
        val m = merges.sumOf { it.remove.size }
        if (vm.dialogs.confirm(ui.t("tidy.mergeAllConfirm", "n" to groups.size, "m" to m))) vm.store.applyMerges(merges)
    }

    SubScreen("🧹 ${ui.t("tidy.title")}") {
        LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            item { Text(ui.t("tidy.dups"), style = MaterialTheme.typography.titleMedium) }
            if (groups.isEmpty()) {
                item { Small(ui.t("tidy.dupsNone")) }
            } else {
                item { Small(ui.t("tidy.dupsIntro")) }
                if (groups.size > 1) {
                    item {
                        Button(onClick = { mergeAll() }, modifier = Modifier.fillMaxWidth()) { Text("🔗 ${ui.t("tidy.mergeAll", "n" to groups.size)}") }
                    }
                }
                items(groups, key = { groupKey(it) }) { g -> DupGroup(g) }
            }
            if (similar.isNotEmpty()) {
                item {
                    TextButton(onClick = { showSimilar = !showSimilar }) {
                        Text((if (showSimilar) "▾ " else "▸ ") + ui.t("tidy.similar", "n" to similar.size), fontWeight = FontWeight.Bold)
                    }
                }
                if (showSimilar) {
                    item { Small(ui.t("tidy.similarIntro")) }
                    items(similar, key = { "s" + groupKey(it) }) { g -> DupGroup(g, quickMerge = false) }
                }
            }
            if (ui.settings.dupIgnore.isNotEmpty()) {
                item {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Small(ui.t("tidy.ignored", "n" to ui.settings.dupIgnore.size), Modifier.weight(1f))
                        TextButton(onClick = { vm.store.updateSettings { it.copy(dupIgnore = emptyList()) } }) { Text(ui.t("tidy.resetIgnored")) }
                    }
                }
            }
            item {
                val noCover = ui.items.count { it.coverData == null && it.coverUrl == null }
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Spacer(Modifier.height(10.dp))
                    Text(ui.t("covers.title"), style = MaterialTheme.typography.titleMedium)
                    Small(ui.t("covers.card", "n" to noCover))
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(onClick = { vm.push(Screen.Covers()) }) { Text("📷 ${ui.t("covers.title")}") }
                        OutlinedButton(onClick = { vm.push(Screen.Rotate()) }) { Text("⟳ ${ui.t("rotate.title")}") }
                    }
                }
            }
            item { BulkByFilter(screen) }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun DupGroup(group: List<Item>, quickMerge: Boolean = true) {
    val ui = LocalUi.current
    val vm = ui.vm
    val scope = rememberCoroutineScope()
    val key = groupKey(group)
    var sel by remember(key) { mutableStateOf(emptySet<String>()) }
    val keepId = remember(group) { mergeGroup(group).keep.id }
    val picked = group.map { it.id }.filter { it in sel }

    fun delete() = scope.launch {
        if (vm.dialogs.confirm(ui.t("bulkEdit.deleteConfirm", "n" to picked.size))) vm.store.removeItems(picked)
    }

    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(vertical = 6.dp)) {
            for (i in group) {
                ItemTile(i, onClick = { sel = if (i.id in sel) sel - i.id else sel + i.id }, selected = i.id in sel)
                Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (quickMerge && i.id == keepId) Pill("✓ ${ui.t("tidy.keep")}")
                    Spacer(Modifier.weight(1f))
                    TextButton(onClick = { vm.push(Screen.Detail(i.id)) }) { Text(ui.t("tidy.open")) }
                }
            }
            FlowRow(Modifier.padding(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (quickMerge) Button(onClick = { vm.store.applyMerges(listOf(mergeGroup(group))) }) { Text("🔗 ${ui.t("tidy.merge")}") }
                OutlinedButton(onClick = { vm.push(Screen.Merge(group.map { it.id })) }) { Text("✎ ${ui.t("tidy.mergeChoose")}") }
                OutlinedButton(onClick = { delete() }, enabled = picked.isNotEmpty() && picked.size < group.size) {
                    Text("🗑 ${ui.t("tidy.deleteSel", "n" to picked.size)}")
                }
                TextButton(onClick = { vm.store.updateSettings { it.copy(dupIgnore = it.dupIgnore + key) } }) { Text(ui.t("tidy.notDup")) }
            }
        }
    }
}

/** Choose entries by kind, selection, status, room and category – then edit, delete or show them. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun BulkByFilter(screen: Screen.Tidy) {
    val ui = LocalUi.current
    val vm = ui.vm
    val scope = rememberCoroutineScope()
    // kept with the screen, so the choice survives opening an entry and coming back
    val state = screen.keep("filters") { mutableStateOf(Filters()) }
    val f = state.value
    fun set(nf: Filters) {
        state.value = nf
    }
    var editing by remember { mutableStateOf(false) }
    val ids = applyFilters(ui.items, f).map { it.id }
    val n = ids.size
    val any = ui.t("any")
    val rooms = ui.rooms

    fun delete() = scope.launch {
        if (vm.dialogs.confirm(ui.t("bulkEdit.deleteConfirm", "n" to n))) vm.store.removeItems(ids)
    }

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Spacer(Modifier.height(10.dp))
        Text(ui.t("tidy.bulk"), style = MaterialTheme.typography.titleMedium)
        Small(ui.t("tidy.bulkIntro"))
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Dropdown(
                        ui.t("lib.kind"), f.kind,
                        listOf(Opt("all", ui.t("kind.all"))) + kinds.map { Opt(it, ui.t("kind.$it.pl")) },
                        { set(f.copy(kind = it)) }, Modifier.weight(1f),
                    )
                    Dropdown(ui.t("lib.scope"), f.scope, scopes.map { Opt(it, ui.t("scope.$it")) }, { set(f.copy(scope = it)) }, Modifier.weight(1f))
                }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Dropdown(
                        ui.t("lib.status"), f.status,
                        listOf(Opt("all", any)) + statuses.map { Opt(it, ui.t("status.${if (f.kind == "all") "book" else f.kind}.$it")) },
                        { set(f.copy(status = it)) }, Modifier.weight(1f),
                    )
                    Dropdown(
                        ui.t("field.room"), f.room,
                        listOf(Opt("all", any)) + rooms.map { Opt(it, it) } + Opt("", ui.t("places.none")),
                        { set(f.copy(room = it)) }, Modifier.weight(1f),
                    )
                }
                CategoryDropdown(f.category, { set(f.copy(category = it)) }, extra = listOf(Opt("all", any)))
                OutlinedTextField(f.q, { set(f.copy(q = it)) }, label = { Text(ui.t("lib.search")) }, singleLine = true, modifier = Modifier.fillMaxWidth())
            }
        }
        Text(ui.t("tidy.match", "n" to n), fontWeight = FontWeight.Bold)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = { editing = true }, enabled = n > 0) { Text("✎ ${ui.t("sel.edit")}") }
            OutlinedButton(onClick = { delete() }, enabled = n > 0) { Text("🗑 ${ui.t("detail.delete")}") }
            TextButton(onClick = {
                vm.stack.clear()
                vm.showInLibrary(f)
            }, enabled = n > 0) { Text(ui.t("tidy.show")) }
        }
    }
    if (editing) BulkEditSheet(ids) { editing = false }
}
