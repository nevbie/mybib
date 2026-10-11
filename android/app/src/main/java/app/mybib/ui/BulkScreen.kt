@file:OptIn(ExperimentalMaterial3Api::class)

package app.mybib.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewModelScope
import app.mybib.AppViewModel
import app.mybib.Screen
import app.mybib.core.Item
import app.mybib.core.bulkTargets
import app.mybib.core.draftOf
import app.mybib.core.enrichPatch
import app.mybib.core.missingInfo
import app.mybib.core.today
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class BulkState {
    var retry by mutableStateOf(false)

    /** idle / running / done / stopped / quota / key */
    var phase by mutableStateOf("idle")
    var done by mutableIntStateOf(0)
    var total by mutableIntStateOf(0)
    var current by mutableStateOf("")
    val found = mutableStateListOf<Item>()
    val missed = mutableStateListOf<Item>()
}

/**
 * Complete covers, publisher, year, ISBN and blurb of all books via Google Books (+ Open Library).
 * Runs in the view model, so opening an entry meanwhile doesn't stop it; closing the screen does.
 */
private fun runBulk(vm: AppViewModel, screen: Screen.Bulk, st: BulkState, targets: List<Item>) = vm.viewModelScope.launch {
    screen.stop = false
    vm.lookup.takeGoogleProblem()
    st.phase = "running"
    st.total = targets.size
    st.done = 0
    st.found.clear()
    st.missed.clear()
    // don't let the phone sleep while it works through hundreds of books
    vm.keepScreenOn = true
    try {
        for ((n, item) in targets.withIndex()) {
            if (screen.stop) {
                st.phase = "stopped"
                return@launch
            }
            st.current = item.title
            val best = try {
                vm.lookup.findBestMatch(item, vm.store.settings.value.googleBooksKey)
            } catch (e: Exception) {
                if (e is CancellationException) throw e
                null
            }
            val problem = vm.lookup.takeGoogleProblem()
            if (problem.isNotEmpty() && best == null) {
                // leave this item untried so the next run picks it up again
                st.phase = problem
                return@launch
            }
            if (best != null) {
                val patch = enrichPatch(item.toJson(), best)
                // without a known author a title-only match may be a different book – ask to check
                val extra = if (item.creators.isEmpty()) draftOf("lookedUp" to today(), "needsCheck" to true) else draftOf("lookedUp" to today())
                vm.store.updateItem(item.id, patch + extra)
                (if (patch.isNotEmpty()) st.found else st.missed).add(item)
            } else {
                vm.store.updateItem(item.id, "lookedUp" to today())
                st.missed.add(item)
            }
            st.done = n + 1
            if (problem.isNotEmpty()) {
                st.phase = problem
                return@launch
            }
            // stay well below Google's per-minute limit
            delay(400)
        }
        st.phase = "done"
    } finally {
        vm.keepScreenOn = false
    }
}

@Composable
fun BulkScreen(screen: Screen.Bulk) {
    val ui = LocalUi.current
    val vm = ui.vm
    val st = screen.keep("bulk") { BulkState() }
    val targets = bulkTargets(ui.items, st.retry)
    val triedBefore = bulkTargets(ui.items, true).size - bulkTargets(ui.items, false).size
    val running = st.phase == "running"

    @Composable
    fun ItemLinks(list: List<Item>, withMissing: Boolean = false) {
        for (i in list.take(if (withMissing) 500 else 30)) {
            Text(
                buildAnnotatedString {
                    withStyle(SpanStyle(color = MaterialTheme.colorScheme.primary)) { append(i.title) }
                    if (withMissing) {
                        withStyle(SpanStyle(fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)) {
                            append("  (${missingInfo(i).joinToString(", ") { ui.t("bulk.field.$it") }})")
                        }
                    }
                },
                modifier = Modifier.fillMaxWidth().clickable { vm.push(Screen.Detail(i.id)) }.padding(vertical = 4.dp),
            )
        }
    }

    SubScreen(
        ui.t("bulk.title"),
        bottomBar = {
            val m = Modifier.fillMaxWidth().navigationBarsPadding().padding(12.dp)
            if (running) {
                OutlinedButton(onClick = { screen.stop = true }, modifier = m) { Text("■ ${ui.t("bulk.stop")}") }
            } else {
                Button(onClick = { runBulk(vm, screen, st, targets) }, enabled = targets.isNotEmpty(), modifier = m) { Text(ui.t("bulk.start", "n" to targets.size)) }
            }
        },
    ) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
            Small(ui.t("bulk.intro"))
            if (ui.settings.googleBooksKey.isEmpty()) {
                HintCard(Modifier.padding(vertical = 10.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(ui.t("bulk.noKey"), color = Color.Black.copy(alpha = 0.87f), fontSize = 14.sp, modifier = Modifier.weight(1f))
                        TextButton(onClick = {
                            vm.pop()
                            vm.tab = 3
                        }) { Text(ui.t("nav.settings")) }
                    }
                }
            }
            if (st.phase == "idle") {
                Text(if (targets.isNotEmpty()) ui.t("bulk.count", "n" to targets.size) else ui.t("bulk.nothing"), Modifier.padding(vertical = 8.dp))
                if (triedBefore > 0) {
                    Row(Modifier.fillMaxWidth().clickable { st.retry = !st.retry }, verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(checked = st.retry, onCheckedChange = { st.retry = it })
                        Text(ui.t("bulk.retry", "n" to triedBefore))
                    }
                }
            } else {
                Spacer(Modifier.height(12.dp))
                LinearProgressIndicator(progress = { if (st.total == 0) 0f else st.done.toFloat() / st.total }, modifier = Modifier.fillMaxWidth())
                Spacer(Modifier.height(6.dp))
                Text("${st.done} / ${st.total} · ✓ ${st.found.size} · – ${st.missed.size}")
                if (running && st.current.isNotEmpty()) Small(st.current, Modifier.padding(top = 6.dp))
                if (st.phase == "done") Text(ui.t("bulk.done", "found" to st.found.size, "missed" to st.missed.size), Modifier.padding(top = 8.dp))
                if (st.phase == "stopped") Text(ui.t("bulk.stopped"), Modifier.padding(top = 8.dp))
                if (st.phase == "quota" || st.phase == "key") {
                    HintCard(Modifier.padding(top = 8.dp)) {
                        Text(ui.t(if (st.phase == "quota") "bulk.quota" else "bulk.badKey"), color = Color.Black.copy(alpha = 0.87f))
                    }
                }
            }
            if (st.found.isNotEmpty()) {
                Text(ui.t("bulk.found", "n" to st.found.size), fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 16.dp, bottom = 4.dp))
                ItemLinks(st.found.reversed())
            }
            if (st.missed.isNotEmpty() && !running) {
                Text(ui.t("bulk.missed", "n" to st.missed.size), fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 16.dp, bottom = 4.dp))
                Small(ui.t("bulk.missedHint"))
                ItemLinks(st.missed, withMissing = true)
            }
        }
    }
}
