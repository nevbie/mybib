@file:OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)

package app.mybib.ui

import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DeleteForever
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.material.icons.filled.FileDownload
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.SaveAlt
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.TableChart
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.mybib.BuildConfig
import app.mybib.Screen
import app.mybib.core.Filters
import app.mybib.core.candidateDraft
import app.mybib.core.kinds
import app.mybib.core.summarizePlaces
import app.mybib.core.toCategory
import kotlinx.coroutines.launch

@Composable
fun AddScreen() {
    val ui = LocalUi.current
    val vm = ui.vm
    val importFile = rememberImporter()
    val ways = listOf(
        Triple(Icons.Filled.QrCodeScanner, ui.t("add.scan") to ui.t("add.scanText")) { vm.push(Screen.Scan()) },
        Triple(Icons.Filled.CameraAlt, ui.t("add.shelf") to (if (ui.settings.claudeKey.isNotEmpty()) ui.t("add.shelfText") else ui.t("add.shelfTextNoKey"))) { vm.push(Screen.Photo("shelf")) },
        Triple(Icons.Filled.Image, ui.t("add.cover") to ui.t("add.coverText")) { vm.push(Screen.Photo("cover")) },
        Triple(Icons.Filled.Search, ui.t("add.search") to ui.t("add.searchText")) { vm.push(Screen.Search { c -> vm.push(Screen.Form(draft = candidateDraft(c))) }) },
        Triple(Icons.Filled.EditNote, ui.t("add.manual") to ui.t("add.manualText")) { vm.push(Screen.Form()) },
        Triple(Icons.Filled.AutoAwesome, ui.t("bulk.title") to ui.t("bulk.short")) { vm.push(Screen.Bulk()) },
        Triple(Icons.Filled.FileDownload, ui.t("add.import") to ui.t("add.importText")) { importFile() },
    )
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Heading(ui.t("nav.add"))
        Spacer(Modifier.height(4.dp))
        for ((icon, texts, onClick) in ways) WayCard(icon, texts.first, texts.second, onClick)
        Small(ui.t("add.tip"))
    }
}

@Composable
private fun WayCard(icon: ImageVector, title: String, text: String, onClick: () -> Unit) {
    Card(onClick = onClick, modifier = Modifier.fillMaxWidth()) {
        ListItem(
            leadingContent = { Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(30.dp)) },
            headlineContent = { Text(title, fontWeight = FontWeight.SemiBold) },
            supportingContent = { Text(text) },
            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        )
    }
}

@Composable
fun PlacesScreen() {
    val ui = LocalUi.current
    val vm = ui.vm
    val store = vm.store
    val scope = rememberCoroutineScope()
    val items = ui.items
    val rooms = ui.rooms
    val byRoom = summarizePlaces(items).toMap()
    val configured = ui.settings.rooms.ifEmpty { app.mybib.core.defaultRoomNames(ui.lang) }
    fun saveRooms(list: List<String>) = store.updateSettings { it.copy(rooms = list.filter { r -> r.isNotEmpty() }.distinct()) }

    fun addRoom() = scope.launch {
        val name = vm.dialogs.prompt(ui.t("places.newRoom"))?.trim()
        if (!name.isNullOrEmpty() && name !in rooms) saveRooms(configured + name)
    }

    fun renameRoom(room: String) = scope.launch {
        val name = vm.dialogs.prompt(ui.t("places.renameRoom", "room" to room), room)?.trim()
        if (name.isNullOrEmpty() || name == room) return@launch
        if (name in rooms && !vm.dialogs.confirm(ui.t("places.mergeConfirm", "room" to room, "name" to name))) return@launch
        store.moveRoom(room, name)
        saveRooms(if (room in configured) configured.map { if (it == room) name else it } else configured)
    }

    fun removeRoom(room: String) = scope.launch {
        val n = byRoom[room] ?: 0
        if (n > 0 && !vm.dialogs.confirm(ui.t("places.removeRoomConfirm", "room" to room, "n" to n))) return@launch
        if (n > 0) store.moveRoom(room, "")
        saveRooms(configured.filter { it != room })
    }

    val owned = items.filter { it.owned }
    val stats = (kinds.map { k -> ui.t("kind.$k.pl") to owned.count { it.kind == k } } + listOf(
        ui.t("places.digital") to owned.count { it.format != "physical" },
        ui.t("places.done") to items.count { it.status == "done" },
        ui.t("places.want") to items.count { it.status == "want" },
        ui.t("scope.lent") to items.count { it.openLoan != null },
        ui.t("scope.wish") to items.size - owned.size,
    )).filter { it.second > 0 }
    val catCount = items.groupingBy { it.category ?: "" }.eachCount()
    val cats = (ui.categories + "").filter { (catCount[it] ?: 0) > 0 }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
        Heading(ui.t("nav.places"))
        Spacer(Modifier.height(10.dp))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            for ((label, n) in stats) {
                Column(Modifier.width(104.dp).border(1.dp, MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(12.dp)).padding(10.dp)) {
                    Text("$n", fontSize = 20.sp, fontWeight = FontWeight.Bold)
                    Small(label)
                }
            }
        }
        if (cats.isNotEmpty() && !(cats.size == 1 && cats.first().isEmpty())) {
            Spacer(Modifier.height(18.dp))
            Text(ui.t("field.category"), style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(6.dp))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                for (c in cats) {
                    AssistChip(
                        onClick = { vm.showInLibrary(Filters(category = c)) },
                        label = { Text("${if (c.isEmpty()) ui.t("cat.none") else ui.catLabel(c)}  ${catCount[c]}") },
                    )
                }
            }
        }
        Spacer(Modifier.height(18.dp))
        Text(ui.t("nav.places"), style = MaterialTheme.typography.titleMedium)
        for (room in rooms) {
            Card(Modifier.fillMaxWidth().padding(vertical = 4.dp).clickable { vm.showInLibrary(Filters(room = room, scope = "owned", format = "physical"), sortBy = "place") }) {
                ListItem(
                    leadingContent = { Text("🏠", fontSize = 20.sp) },
                    headlineContent = { Text(room) },
                    supportingContent = { Text("${byRoom[room] ?: 0}") },
                    trailingContent = {
                        Row {
                            IconButton(onClick = { renameRoom(room) }) { Icon(Icons.Outlined.Edit, contentDescription = ui.t("places.rename")) }
                            IconButton(onClick = { removeRoom(room) }) { Icon(Icons.Filled.Close, contentDescription = ui.t("places.remove")) }
                        }
                    },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                )
            }
        }
        if ((byRoom[""] ?: 0) > 0) {
            Card(Modifier.fillMaxWidth().padding(vertical = 4.dp).clickable { vm.showInLibrary(Filters(room = "", scope = "owned", format = "physical")) }) {
                ListItem(
                    leadingContent = { Text("❔", fontSize = 20.sp) },
                    headlineContent = { Text(ui.t("places.none")) },
                    supportingContent = { Text("${byRoom[""]}") },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                )
            }
        }
        Spacer(Modifier.height(8.dp))
        OutlinedButton(onClick = { addRoom() }) {
            Icon(Icons.Filled.Add, contentDescription = null)
            Spacer(Modifier.width(8.dp))
            Text(ui.t("places.addRoom"))
        }
        Spacer(Modifier.height(8.dp))
        Small(ui.t("places.tip"))
    }
}

private val models = listOf("claude-opus-5-5" to "Claude Opus 5.5", "claude-sonnet-5-5" to "Claude Sonnet 5.5")

@Composable
fun SettingsScreen() {
    val ui = LocalUi.current
    val vm = ui.vm
    val store = vm.store
    val st = ui.settings
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var showKey by remember { mutableStateOf(false) }
    var claudeKey by remember { mutableStateOf(st.claudeKey) }
    var googleKey by remember { mutableStateOf(st.googleBooksKey) }
    var googleHow by remember { mutableStateOf(false) }
    val exportJsonFile = rememberJsonExporter()
    val importFile = rememberImporter()
    val cats = ui.categories
    val catCount = ui.items.mapNotNull { it.category }.groupingBy { it }.eachCount()
    fun saveCats(list: List<String>) = store.updateSettings { it.copy(categories = list.filter { c -> c.isNotEmpty() }.distinct()) }

    fun addCategory() = scope.launch {
        val name = vm.dialogs.prompt(ui.t("cat.new"))?.trim()
        if (!name.isNullOrEmpty()) saveCats(cats + toCategory(name)!!)
    }

    fun renameCategory(c: String) = scope.launch {
        val label = ui.catLabel(c)
        val name = vm.dialogs.prompt(ui.t("cat.rename", "name" to label), label)?.trim()
        if (name.isNullOrEmpty() || name == label) return@launch
        val to = toCategory(name)!!
        if (to in cats && !vm.dialogs.confirm(ui.t("cat.mergeConfirm", "from" to label, "to" to ui.catLabel(to)))) return@launch
        store.moveCategory(c, to)
        saveCats(cats.map { if (it == c) to else it })
    }

    fun removeCategory(c: String) = scope.launch {
        if (!vm.dialogs.confirm(ui.t("cat.removeConfirm", "name" to ui.catLabel(c), "n" to (catCount[c] ?: 0)))) return@launch
        store.moveCategory(c, "")
        saveCats(cats.filter { it != c })
    }

    fun wipe() = scope.launch {
        if (!vm.dialogs.confirm(ui.t("data.wipeConfirm", "n" to store.items.value.size))) return@launch
        if (vm.dialogs.prompt(ui.t("data.wipeType"))?.trim() == "OK") store.replaceAll(emptyList())
    }

    @Composable
    fun H(text: String) = Text(text, style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 22.dp, bottom = 6.dp))

    @Composable
    fun ActionButton(icon: ImageVector, text: String, onClick: () -> Unit) = OutlinedButton(onClick = onClick, modifier = Modifier.fillMaxWidth()) {
        Icon(icon, contentDescription = null)
        Spacer(Modifier.width(8.dp))
        Text(text, modifier = Modifier.weight(1f))
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
        Heading(ui.t("nav.settings"))
        H(ui.t("settings.lang"))
        Segmented(listOf("de" to "Deutsch", "en" to "English"), ui.lang, { l -> store.updateSettings { it.copy(lang = l) } })

        H(ui.t("settings.ai"))
        Small(ui.t("settings.aiText"))
        OutlinedTextField(
            value = claudeKey,
            onValueChange = { v ->
                claudeKey = v
                store.updateSettings { it.copy(claudeKey = v.trim()) }
            },
            label = { Text(ui.t("settings.claudeKey")) },
            placeholder = { Text("sk-ant-…") },
            singleLine = true,
            visualTransformation = if (showKey) VisualTransformation.None else PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(autoCorrectEnabled = false, keyboardType = KeyboardType.Password),
            trailingIcon = {
                IconButton(onClick = { showKey = !showKey }) { Icon(if (showKey) Icons.Filled.VisibilityOff else Icons.Filled.Visibility, contentDescription = null) }
            },
            modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
        )
        Dropdown(
            ui.t("settings.model"),
            if (models.any { it.first == st.claudeModel }) st.claudeModel else models.first().first,
            models.map { (id, name) -> Opt(id, "$name – ${ui.t("settings.model.$id")}") },
            { m -> store.updateSettings { it.copy(claudeModel = m) } },
        )
        Spacer(Modifier.height(6.dp))
        Small(ui.t("settings.aiPrivacy"))

        H(ui.t("settings.lookup"))
        Small(ui.t("settings.lookupText"))
        OutlinedTextField(
            value = googleKey,
            onValueChange = { v ->
                googleKey = v
                store.updateSettings { it.copy(googleBooksKey = v.trim()) }
            },
            label = { Text(ui.t("settings.googleKey")) },
            placeholder = { Text(ui.t("optional")) },
            singleLine = true,
            keyboardOptions = KeyboardOptions(autoCorrectEnabled = false),
            modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
        )
        TextButton(onClick = { googleHow = !googleHow }) { Text((if (googleHow) "▾ " else "▸ ") + ui.t("settings.googleHow")) }
        if (googleHow) {
            for (n in 1..4) Text("$n. ${ui.t("settings.googleHow$n")}", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(start = 8.dp, bottom = 6.dp))
        }

        H(ui.t("settings.categories"))
        Small(ui.t("settings.categoriesText"))
        Card(Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
            for (c in cats) {
                Row(Modifier.fillMaxWidth().padding(start = 16.dp), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                    Text("${ui.catLabel(c)}  (${catCount[c] ?: 0})", modifier = Modifier.weight(1f))
                    IconButton(onClick = { renameCategory(c) }) { Icon(Icons.Outlined.Edit, contentDescription = ui.t("places.rename"), modifier = Modifier.size(20.dp)) }
                    IconButton(onClick = { removeCategory(c) }) { Icon(Icons.Filled.Close, contentDescription = ui.t("places.remove"), modifier = Modifier.size(20.dp)) }
                }
            }
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = { addCategory() }) {
                Icon(Icons.Filled.Add, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text(ui.t("cat.add"))
            }
            if (st.categories.isNotEmpty()) {
                TextButton(onClick = {
                    scope.launch { if (vm.dialogs.confirm(ui.t("cat.resetConfirm"))) store.updateSettings { it.copy(categories = emptyList()) } }
                }) { Text(ui.t("cat.reset")) }
            }
        }

        H(ui.t("settings.data"))
        Small(ui.t("settings.dataText", "n" to ui.items.size))
        Spacer(Modifier.height(8.dp))
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            ActionButton(Icons.Filled.SaveAlt, ui.t("data.exportJson")) { exportJsonFile() }
            ActionButton(Icons.Filled.Share, ui.t("data.exportJsonShare")) { shareFile(ctx, "mybib-${stamp()}.json", exportJson(ui), "application/json") }
            ActionButton(Icons.Outlined.TableChart, ui.t("data.exportCsvShare")) { shareFile(ctx, "mybib-${stamp()}.csv", exportCsv(ui), "text/csv") }
            ActionButton(Icons.Filled.FileDownload, ui.t("data.import")) { importFile() }
            TextButton(onClick = { wipe() }, enabled = ui.items.isNotEmpty()) {
                Icon(Icons.Filled.DeleteForever, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                Spacer(Modifier.width(8.dp))
                Text(ui.t("data.wipe"), color = MaterialTheme.colorScheme.error)
            }
        }
        Spacer(Modifier.height(24.dp))
        Small(
            "mybib · ${ui.t("settings.about")} · ${ui.t("settings.version", "v" to BuildConfig.VERSION_NAME)}",
            Modifier.fillMaxWidth().padding(bottom = 24.dp),
        )
    }
}
