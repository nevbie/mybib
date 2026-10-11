package app.mybib

import app.mybib.core.Candidate
import app.mybib.core.Draft

/**
 * Screens shown on top of the tabs. Each entry keeps its own UI state ([keep]), so a form
 * still has its input when the online search on top of it returns.
 */
sealed class Screen {
    private val kept = mutableMapOf<String, Any>()

    @Suppress("UNCHECKED_CAST")
    fun <T : Any> keep(key: String, init: () -> T): T = kept.getOrPut(key, init) as T

    /** Called when the screen is closed. */
    open fun onClose() {}

    class Detail(val id: String) : Screen()

    /** New entry (optionally prefilled from [draft]) or edit an existing one ([id]). */
    class Form(val id: String? = null, val draft: Draft? = null) : Screen()

    /** Online search; [onPick] gets the chosen result after the search screen closed. */
    class Search(val kind: String = "book", val title: String = "", val creator: String = "", val onPick: (Candidate) -> Unit) : Screen()

    class Scan : Screen()

    /** "shelf" or "cover" */
    class Photo(val mode: String) : Screen()

    /** Duplicates, bulk edit and bulk delete. */
    class Tidy : Screen()

    /** Add cover photos to existing entries: [ids], or all entries without a cover when null. */
    class Covers(val ids: List<String>? = null) : Screen()

    /** Turn own cover photos upright: [ids], or all entries with an own cover photo when null. */
    class Rotate(val ids: List<String>? = null) : Screen()

    /** Merge [ids] into one entry, choosing per field whose value to keep. */
    class Merge(val ids: List<String>) : Screen()

    class Bulk : Screen() {
        @Volatile var stop = false

        override fun onClose() {
            stop = true
        }
    }
}
