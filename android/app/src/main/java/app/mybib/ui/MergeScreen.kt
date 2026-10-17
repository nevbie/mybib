package app.mybib.ui

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.mybib.Screen
import app.mybib.core.Item
import app.mybib.core.differingFields
import app.mybib.core.mergeGroup
import app.mybib.core.mergeValue
import app.mybib.core.mergeWithChoices

private val fieldLabel = mapOf(
    "cover" to "merge.cover", "spine" to "merge.spine", "title" to "field.title", "subtitle" to "field.subtitle", "creators" to "merge.creators",
    "series" to "field.seriesOnly", "volume" to "field.volume", "publisher" to "field.publisher", "year" to "field.year",
    "isbn" to "field.isbn", "language" to "field.language", "pages" to "field.pages", "kind" to "field.kind",
    "format" to "field.format", "category" to "field.category", "room" to "field.room", "description" to "merge.description",
    "status" to "detail.status", "rating" to "rating",
)

/**
 * Merge several entries into one and choose, field by field, whose value to keep (cover, author, volume …).
 * Notes, tags and loans of all entries are kept together.
 */
@Composable
fun MergeScreen(screen: Screen.Merge) {
    val ui = LocalUi.current
    val vm = ui.vm
    val group = screen.ids.mapNotNull { ui.byId(it) }
    // kept with the screen, so the choices survive opening an entry
    val choices = screen.keep("choices") { mutableStateMapOf<String, String>() }
    if (group.size < 2) {
        SubScreen("🔗 ${ui.t("merge.title", "n" to group.size)}") {}
        return
    }
    val fields = remember(group) { differingFields(group) }
    // default choice per field = what the automatic merge would keep
    val auto = remember(group) { mergeGroup(group).keep }
    fun chosen(f: String) = choices[f] ?: group.firstOrNull { mergeValue(it, f) == mergeValue(auto, f) }?.id ?: group.first().id

    fun merge() {
        val m = mergeWithChoices(group, fields.associateWith { chosen(it) })
        vm.store.applyMerges(listOf(m))
        vm.pop()
        vm.push(Screen.Detail(m.keep.id))
    }

    @Composable
    fun Value(i: Item, f: String) {
        val v = mergeValue(i, f)
        when {
            v.isEmpty() -> Text(ui.t("merge.empty"), color = MaterialTheme.colorScheme.onSurfaceVariant)
            f == "cover" -> CoverImage(i)
            f == "spine" -> coverBitmap(v)?.let { Image(it, contentDescription = null, modifier = Modifier.height(96.dp)) } ?: Text(ui.t("merge.spine"))
            f == "kind" -> Text(ui.t("kind.$v"))
            f == "format" -> Text(ui.t("format.$v"))
            f == "status" -> Text(ui.t("status.${i.kind}.$v"))
            f == "category" -> Text(ui.catLabel(v))
            f == "rating" -> Text("★".repeat(i.rating))
            f == "description" -> Text(if (v.length > 140) v.take(140) + " …" else v)
            else -> Text(v)
        }
    }

    SubScreen(
        "🔗 ${ui.t("merge.title", "n" to group.size)}",
        bottomBar = {
            Button(onClick = { merge() }, modifier = Modifier.fillMaxWidth().navigationBarsPadding().padding(12.dp)) {
                Text("🔗 ${ui.t("merge.apply")}")
            }
        },
    ) {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            item { Small(ui.t("merge.intro")) }
            if (fields.isEmpty()) item { Text(ui.t("merge.same")) }
            items(fields) { f ->
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(ui.t(fieldLabel[f] ?: f), fontWeight = FontWeight.SemiBold)
                        for (i in group) {
                            val on = chosen(f) == i.id
                            Row(
                                Modifier.fillMaxWidth()
                                    .border(1.dp, if (on) MaterialTheme.colorScheme.primary else Color.Transparent, RoundedCornerShape(8.dp))
                                    .clickable { choices[f] = i.id }
                                    .padding(horizontal = 4.dp, vertical = 2.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                RadioButton(selected = on, onClick = { choices[f] = i.id })
                                Spacer(Modifier.width(4.dp))
                                Value(i, f)
                            }
                        }
                    }
                }
            }
            item { Small(ui.t("merge.combined")) }
        }
    }
}
