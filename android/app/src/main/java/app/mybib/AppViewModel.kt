package app.mybib

import android.app.Application
import android.content.Context
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import app.mybib.core.Filters
import app.mybib.ui.Dialogs
import org.json.JSONObject

/** App-wide UI state that outlives a screen (tab, filters, sort, the screen stack). */
class AppViewModel(app: Application) : AndroidViewModel(app) {
    private val a = app as MybibApp
    val store get() = a.store
    val strings get() = a.strings
    val lookup get() = a.lookup
    val claude get() = a.claude
    val dialogs = Dialogs()

    // where you were last time: tab, filters, sort, view and scroll position (restored from "ui" prefs)
    private val prefs = app.getSharedPreferences("ui", Context.MODE_PRIVATE)
    private val saved = try {
        JSONObject(prefs.getString("state", null) ?: "{}")
    } catch (_: Exception) {
        JSONObject()
    }

    var tab by mutableIntStateOf(saved.optInt("tab", 0).coerceIn(0, 3))
    var filters by mutableStateOf(filtersFrom(saved.optJSONObject("filters")))
    var sort by mutableStateOf(saved.optString("sort", "title"))

    /** "list", "compact", "grid" or "shelf" */
    var view by mutableStateOf(saved.optString("view", "list").takeIf { it in listOf("list", "compact", "grid", "shelf") } ?: "list")
    var keepScreenOn by mutableStateOf(false)

    // library state kept while other tabs or screens are shown
    val libraryList = LazyListState(saved.optInt("listIndex", 0), saved.optInt("listOffset", 0))
    val libraryGrid = LazyGridState(saved.optInt("gridIndex", 0), saved.optInt("gridOffset", 0))
    var libraryMore by mutableStateOf(false)

    /** Remember tab, filters, sort, view and scroll position for the next start. */
    fun saveUi() {
        val f = filters
        val state = JSONObject()
            .put("tab", tab)
            .put("sort", sort)
            .put("view", view)
            .put("listIndex", libraryList.firstVisibleItemIndex)
            .put("listOffset", libraryList.firstVisibleItemScrollOffset)
            .put("gridIndex", libraryGrid.firstVisibleItemIndex)
            .put("gridOffset", libraryGrid.firstVisibleItemScrollOffset)
            .put(
                "filters",
                JSONObject().put("q", f.q).put("kind", f.kind).put("status", f.status).put("scope", f.scope).put("format", f.format)
                    .put("room", f.room).put("category", f.category).put("language", f.language).put("minRating", f.minRating),
            )
        prefs.edit().putString("state", state.toString()).apply()
    }

    /** bulk edit: null = normal mode, otherwise the selected ids */
    var selection by mutableStateOf<Set<String>?>(null)

    /** Screens on top of the tabs; the last one is shown. */
    val stack = mutableStateListOf<Screen>()

    fun push(s: Screen) {
        stack.add(s)
    }

    fun pop() {
        stack.removeLastOrNull()?.onClose()
    }

    /** Jump to the library showing only what matches [f]. */
    fun showInLibrary(f: Filters, sortBy: String? = null) {
        filters = f
        if (sortBy != null) sort = sortBy
        tab = 0
    }
}

private fun filtersFrom(o: JSONObject?): Filters {
    if (o == null) return Filters()
    return Filters(
        q = o.optString("q", ""),
        kind = o.optString("kind", "all"),
        status = o.optString("status", "all"),
        scope = o.optString("scope", "all"),
        format = o.optString("format", "all"),
        room = o.optString("room", "all"),
        category = o.optString("category", "all"),
        minRating = o.optInt("minRating", 0),
        language = o.optString("language", "all"),
    )
}
