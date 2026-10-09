package app.mybib.core

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/**
 * All data lives on this device: one JSON file for the catalogue, one for settings.
 * Writes are debounced so typing a note doesn't rewrite the file on every key.
 * The Android app passes the Flutter app's documents directory, so an update keeps the data.
 */
class Store(
    val dir: File,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO),
) {
    private val _items = MutableStateFlow<List<Item>>(emptyList())
    private val _settings = MutableStateFlow(Settings())
    private val _ready = MutableStateFlow(false)
    val items: StateFlow<List<Item>> = _items.asStateFlow()
    val settings: StateFlow<Settings> = _settings.asStateFlow()
    val ready: StateFlow<Boolean> = _ready.asStateFlow()

    private var saveJob: Job? = null
    private val lock = Any()

    fun byId(id: String) = _items.value.firstOrNull { it.id == id }

    /** Read both files (blocking – call off the main thread). */
    fun load() {
        try {
            val f = File(dir, "items.json")
            if (f.exists()) {
                val data = parseJson(f.readText()).obj
                _items.value = data?.get("items").arr?.mapNotNull { it.obj }?.map { normalizeItem(it) } ?: emptyList()
            }
            val s = File(dir, "settings.json")
            if (s.exists()) parseJson(s.readText()).obj?.let { _settings.value = Settings.fromJson(it) }
        } catch (e: Exception) {
            System.err.println("loading failed: $e")
        }
        _ready.value = true
    }

    private fun changed() {
        synchronized(lock) {
            saveJob?.cancel()
            saveJob = scope.launch {
                delay(400)
                save()
            }
        }
    }

    private fun write(name: String, text: String) {
        dir.mkdirs()
        val f = File(dir, name)
        val tmp = File(dir, "$name.tmp")
        tmp.writeText(text)
        Files.move(tmp.toPath(), f.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
    }

    /** Write the catalogue now (atomically: temp file, then rename). Blocking. */
    fun save() = synchronized(lock) {
        write("items.json", draftOf("version" to 1, "items" to _items.value.map { it.toJson() }).let(::j).toString())
    }

    private fun saveSettings() = synchronized(lock) { write("settings.json", _settings.value.toJson().toString()) }

    /** Write everything that is still pending now (app goes to the background, tests). Blocking. */
    fun flush() {
        synchronized(lock) { saveJob?.cancel() }
        save()
        saveSettings()
    }

    fun addItems(drafts: List<Draft>): List<Item> {
        val now = nowIso()
        val created = drafts.map { normalizeItem(it + draftOf("id" to null, "addedAt" to now, "updatedAt" to now)) }
        _items.update { it + created }
        changed()
        return created
    }

    fun updateItem(id: String, patch: Draft) = updateItems(listOf(id)) { patch }

    fun updateItem(id: String, vararg patch: Pair<String, Any?>) = updateItem(id, draftOf(*patch))

    /** Apply a (per-item) change to many items at once – bulk edit, room/category moves. */
    fun updateItems(ids: Collection<String>, patch: (Item) -> Draft) {
        val set = ids.toSet()
        val now = nowIso()
        _items.update { list -> list.map { i -> if (i.id in set) i.copyWith(patch(i) + draftOf("id" to i.id, "updatedAt" to now)) else i } }
        changed()
    }

    fun removeItems(ids: Collection<String>) {
        val set = ids.toSet()
        _items.update { list -> list.filter { it.id !in set } }
        changed()
    }

    fun importItems(incoming: List<Item>, updateOnly: Boolean = false): MergeResult {
        val r = mergeItems(_items.value, incoming, updateOnly)
        _items.value = r.items
        changed()
        return r
    }

    fun replaceAll(list: List<Item>) {
        _items.value = list.toList()
        changed()
    }

    fun moveRoom(from: String, to: String) =
        updateItems(_items.value.filter { (it.room ?: "") == from }.map { it.id }) { draftOf("room" to to.ifEmpty { null }) }

    fun moveCategory(from: String, to: String) =
        updateItems(_items.value.filter { it.category == from }.map { it.id }) { draftOf("category" to to.ifEmpty { null }) }

    fun updateSettings(s: Settings) {
        _settings.value = s
        scope.launch { saveSettings() }
    }

    fun updateSettings(change: (Settings) -> Settings) = updateSettings(change(_settings.value))

    fun rooms(lang: String) = allRooms(_items.value, _settings.value.rooms, defaultRoomNames(lang))

    fun categories() = allCategories(_settings.value.categories, _items.value.map { it.category })
}
