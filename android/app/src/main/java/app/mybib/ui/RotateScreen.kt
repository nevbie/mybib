package app.mybib.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewModelScope
import app.mybib.Screen
import app.mybib.core.RecognizeError
import app.mybib.core.sortItems
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Covers per request – small thumbnails, so a batch stays cheap and fast. */
private const val BATCH = 12

/** Kept with the screen, so progress and results survive opening an entry. */
class RotateState {
    var list by mutableStateOf<List<String>?>(null)
    var busy by mutableStateOf("")
    var turned by mutableStateOf(emptySet<String>())
}

/**
 * Turn own cover photos upright: automatically (Claude looks at each cover and says how far to turn it)
 * or by hand, 90° per tap. Without [Screen.Rotate.ids]: all entries with an own cover photo.
 */
@Composable
fun RotateScreen(screen: Screen.Rotate) {
    val ui = LocalUi.current
    val vm = ui.vm
    val scope = rememberCoroutineScope()
    val st = screen.keep("rotate") { RotateState() }
    val hasKey = ui.settings.claudeKey.isNotEmpty()
    val list = st.list ?: run {
        val base = screen.ids?.mapNotNull { ui.byId(it) } ?: ui.items
        sortItems(base.filter { it.coverData != null }, "place").map { it.id }.also { st.list = it }
    }
    val live = list.mapNotNull { ui.byId(it) }.filter { it.coverData != null }

    suspend fun turn(id: String, deg: Int) {
        val data = vm.store.byId(id)?.coverData ?: return
        vm.store.updateItem(id, "coverData" to withContext(Dispatchers.Default) { rotateDataUrl(data, deg) })
    }

    // runs in the view model, so it goes on while an entry is open
    fun auto() = vm.viewModelScope.launch {
        val s = vm.store.settings.value
        val done = mutableSetOf<String>()
        try {
            for (start in live.indices step BATCH) {
                val batch = live.subList(start, minOf(start + BATCH, live.size))
                st.busy = ui.t("rotate.checking", "i" to minOf(start + BATCH, live.size), "n" to live.size)
                val jpegs = batch.map { dataUrlBytes(it.coverData!!) }
                val degs = vm.claude.detectRotations(s.claudeKey, s.claudeModel, jpegs)
                for ((k, item) in batch.withIndex()) {
                    if (degs[k] != 0) {
                        turn(item.id, degs[k])
                        done += item.id
                    }
                }
            }
            vm.dialogs.info(ui.t("rotate.done", "n" to done.size, "total" to live.size))
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            vm.dialogs.info(if (e is RecognizeError) ui.t("ai.err.${e.code}") else e.toString())
        } finally {
            st.turned = done
            st.busy = ""
        }
    }

    SubScreen("⟳ ${ui.t("rotate.title")}") {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Small(if (hasKey) ui.t("rotate.intro") else ui.t("rotate.introNoKey"))
                    Button(onClick = { auto() }, enabled = hasKey && live.isNotEmpty() && st.busy.isEmpty(), modifier = Modifier.fillMaxWidth()) {
                        Text("✨ ${ui.t("rotate.auto", "n" to live.size)}")
                    }
                    if (st.busy.isNotEmpty()) {
                        Row(Modifier.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                            CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                            Spacer(Modifier.width(12.dp))
                            Text(st.busy)
                        }
                    }
                    if (live.isEmpty()) Small(ui.t("rotate.none"))
                }
            }
            items(live, key = { it.id }) { i ->
                Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    CoverImage(i)
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(i.title, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        if (i.id in st.turned) Pill("⟳ ${ui.t("rotate.turned")}")
                    }
                    IconButton(onClick = { scope.launch { turn(i.id, 270) } }, enabled = st.busy.isEmpty()) {
                        Text("⟲", fontSize = 22.sp, modifier = Modifier.semantics { contentDescription = ui.t("rotate.left") })
                    }
                    IconButton(onClick = { scope.launch { turn(i.id, 90) } }, enabled = st.busy.isEmpty()) {
                        Text("⟳", fontSize = 22.sp, modifier = Modifier.semantics { contentDescription = ui.t("rotate.right") })
                    }
                }
                HorizontalDivider()
            }
        }
    }
}
