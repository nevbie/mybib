package app.mybib

import android.app.Application
import app.mybib.core.Claude
import app.mybib.core.Lookup
import app.mybib.core.Store
import app.mybib.core.Strings
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class MybibApp : Application() {
    lateinit var store: Store
        private set

    /** All texts, bundled from shared/strings.json. */
    val strings: Strings by lazy { Strings.parse(assets.open("strings.json").bufferedReader().use { it.readText() }) }
    val lookup = Lookup()
    val claude = Claude()

    override fun onCreate() {
        super.onCreate()
        // Same directory as Flutter's getApplicationDocumentsDirectory() (app_flutter),
        // so updating from the Flutter build keeps the catalogue.
        store = Store(getDir("flutter", MODE_PRIVATE))
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch { store.load() }
    }
}
