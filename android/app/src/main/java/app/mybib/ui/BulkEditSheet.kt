@file:OptIn(ExperimentalMaterial3Api::class)

package app.mybib.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
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
import app.mybib.core.draftOf
import app.mybib.core.formats
import app.mybib.core.j
import app.mybib.core.kinds
import app.mybib.core.statuses
import kotlinx.coroutines.launch

private const val UNCHANGED = "\u0000unchanged"
private const val NONE = "\u0000none"
private const val NEW = "\u0000new"

/**
 * Change room, category, status, rating, kind, format, wishlist, recommendation or tags of
 * many items at once. Only what is changed here is applied.
 */
@Composable
fun BulkEditSheet(ids: List<String>, onDismiss: () -> Unit) {
    val ui = LocalUi.current
    val vm = ui.vm
    val scope = rememberCoroutineScope()
    val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var room by remember { mutableStateOf(UNCHANGED) }
    var category by remember { mutableStateOf(UNCHANGED) }
    var status by remember { mutableStateOf(UNCHANGED) }
    var kind by remember { mutableStateOf(UNCHANGED) }
    var format by remember { mutableStateOf(UNCHANGED) }
    var owned by remember { mutableStateOf(UNCHANGED) }
    var recommend by remember { mutableStateOf(UNCHANGED) }
    var rating by remember { mutableStateOf(UNCHANGED) }
    var removeTag by remember { mutableStateOf("") }
    var newRoom by remember { mutableStateOf("") }
    var addTag by remember { mutableStateOf("") }
    var checked by remember { mutableStateOf(false) }

    val items = ids.mapNotNull { ui.byId(it) }
    val live = items.map { it.id }
    val n = live.size
    val kindsUsed = items.map { it.kind }.toSet()
    val labelKind = if (kindsUsed.size == 1) kindsUsed.first() else "book"
    val allTags = items.flatMap { it.tags }.toSet().sorted()
    val un = Opt(UNCHANGED, ui.t("bulkEdit.unchanged"))
    val changes = listOf(
        room != UNCHANGED && (room != NEW || newRoom.isNotBlank()),
        category != UNCHANGED, status != UNCHANGED, kind != UNCHANGED, format != UNCHANGED,
        owned != UNCHANGED, recommend != UNCHANGED, rating != UNCHANGED,
        addTag.isNotBlank(), removeTag.isNotEmpty(), checked,
    ).count { it }

    fun apply() {
        val patch = linkedMapOf<String, Any?>()
        if (room != UNCHANGED) {
            val r = if (room == NEW) newRoom.trim() else if (room == NONE) "" else room
            if (room != NEW || r.isNotEmpty()) patch["room"] = r.ifEmpty { null }
        }
        if (category != UNCHANGED) patch["category"] = if (category == NONE) null else category
        if (status != UNCHANGED) patch["status"] = status
        if (kind != UNCHANGED) patch["kind"] = kind
        if (format != UNCHANGED) patch["format"] = format
        if (owned != UNCHANGED) patch["owned"] = owned == "yes"
        if (recommend != UNCHANGED) patch["recommend"] = recommend == "yes"
        if (rating != UNCHANGED) patch["rating"] = rating.toInt()
        if (checked) patch["needsCheck"] = false
        val tag = addTag.trim()
        val rm = removeTag
        vm.store.updateItems(live) { i ->
            val p = patch.mapValues { j(it.value) }
            if (tag.isNotEmpty() || rm.isNotEmpty()) p + draftOf("tags" to (i.tags.filter { it != rm } + listOfNotNull(tag.ifEmpty { null })).distinct()) else p
        }
        onDismiss()
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheet) {
        Column(Modifier.fillMaxWidth().imePadding()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(ui.t("bulkEdit.title", "n" to n), fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                IconButton(onClick = onDismiss) { Icon(Icons.Filled.Close, contentDescription = ui.t("close")) }
            }
            Column(
                Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Small(ui.t("bulkEdit.intro"))
                Dropdown(
                    ui.t("field.room"), room,
                    listOf(un) + ui.rooms.map { Opt(it, it) } + Opt(NONE, ui.t("places.none")) + Opt(NEW, ui.t("bulkEdit.newRoom")),
                    { room = it },
                )
                if (room == NEW) {
                    OutlinedTextField(newRoom, { newRoom = it }, label = { Text(ui.t("places.newRoom")) }, singleLine = true, modifier = Modifier.fillMaxWidth())
                }
                CategoryDropdown(category, { category = it }, extra = listOf(un), noneValue = NONE)
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Dropdown(
                        ui.t("detail.status"), status,
                        listOf(un) + statuses.map { Opt(it, if (it == "none") ui.t("bulkEdit.noStatus") else ui.t("status.$labelKind.$it")) },
                        { status = it }, Modifier.weight(1f),
                    )
                    Dropdown(
                        ui.t("rating"), rating,
                        listOf(un, Opt("0", ui.t("bulkEdit.noRating"))) + (1..5).map { Opt("$it", "★".repeat(it)) },
                        { rating = it }, Modifier.weight(1f),
                    )
                }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Dropdown(ui.t("field.kind"), kind, listOf(un) + kinds.map { Opt(it, ui.t("kind.$it")) }, { kind = it }, Modifier.weight(1f))
                    Dropdown(ui.t("field.format"), format, listOf(un) + formats.map { Opt(it, ui.t("format.$it")) }, { format = it }, Modifier.weight(1f))
                }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Dropdown(ui.t("scope.wish"), owned, listOf(un, Opt("yes", ui.t("bulkEdit.owned")), Opt("no", ui.t("scope.wish"))), { owned = it }, Modifier.weight(1f))
                    Dropdown("👍 ${ui.t("detail.recommend")}", recommend, listOf(un, Opt("yes", ui.t("bulkEdit.yes")), Opt("no", ui.t("bulkEdit.no"))), { recommend = it }, Modifier.weight(1f))
                }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    OutlinedTextField(
                        addTag, { addTag = it },
                        label = { Text(ui.t("bulkEdit.addTag")) },
                        placeholder = { Text(ui.t("form.tagsHint")) },
                        singleLine = true,
                        modifier = Modifier.weight(1f),
                    )
                    if (allTags.isNotEmpty()) {
                        Dropdown(ui.t("bulkEdit.removeTag"), removeTag, listOf(Opt("", "–")) + allTags.map { Opt(it, it) }, { removeTag = it }, Modifier.weight(1f))
                    }
                }
                Row(Modifier.fillMaxWidth().clickable { checked = !checked }, verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(checked = checked, onCheckedChange = { checked = it })
                    Text(ui.t("bulkEdit.checked"))
                }
            }
            Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                Button(onClick = { apply() }, enabled = changes > 0 && n > 0, modifier = Modifier.weight(1f)) { Text(ui.t("bulkEdit.apply", "n" to n)) }
                IconButton(
                    enabled = n > 0,
                    onClick = {
                        scope.launch {
                            if (vm.dialogs.confirm(ui.t("bulkEdit.deleteConfirm", "n" to n))) {
                                vm.store.removeItems(live)
                                onDismiss()
                            }
                        }
                    },
                ) { Icon(Icons.Filled.DeleteOutline, contentDescription = ui.t("detail.delete"), tint = MaterialTheme.colorScheme.error) }
            }
        }
    }
}
