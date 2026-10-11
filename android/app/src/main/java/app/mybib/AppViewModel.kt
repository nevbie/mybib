package app.mybib

import android.app.Application
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import app.mybib.core.Filters
import app.mybib.ui.Dialogs

/** App-wide UI state that outlives a screen (tab, filters, sort, the screen stack). */
class AppViewModel(app: Application) : AndroidViewModel(app) {
    private val a = app as MybibApp
    val store get() = a.store
    val strings get() = a.strings
    val lookup get() = a.lookup
    val claude get() = a.claude
    val dialogs = Dialogs()

    var tab by mutableIntStateOf(0)
    var filters by mutableStateOf(Filters())
    var sort by mutableStateOf("title")
    var keepScreenOn by mutableStateOf(false)

    // library state kept while other tabs or screens are shown
    val libraryList = LazyListState()
    var libraryMore by mutableStateOf(false)

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
