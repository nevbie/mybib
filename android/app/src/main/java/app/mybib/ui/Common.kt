@file:OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class, ExperimentalFoundationApi::class)

package app.mybib.ui

import android.content.Context
import android.graphics.BitmapFactory
import android.util.LruCache
import android.widget.Toast
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.CheckBox
import androidx.compose.material.icons.filled.CheckBoxOutlineBlank
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.PopupProperties
import app.mybib.AppViewModel
import app.mybib.core.Item
import app.mybib.core.Settings
import app.mybib.core.allCategories
import app.mybib.core.allRooms
import app.mybib.core.categoryLabel
import app.mybib.core.defaultCategoryGroups
import app.mybib.core.defaultRoomNames
import coil.compose.AsyncImage
import kotlinx.coroutines.CompletableDeferred
import java.util.Base64
import java.util.Locale

/** Snapshot of the data a screen needs (like Flutter's AppScope): items, settings, language. */
class Ui(val vm: AppViewModel, val items: List<Item>, val settings: Settings, val lang: String) {
    val store get() = vm.store

    fun t(key: String, vararg vars: Pair<String, Any?>) = vm.strings.t(lang, key, vars.toMap())

    fun catLabel(c: String) = categoryLabel(c, lang)

    fun byId(id: String) = items.firstOrNull { it.id == id }

    val rooms: List<String> by lazy { allRooms(items, settings.rooms, defaultRoomNames(lang)) }
    val categories: List<String> by lazy { allCategories(settings.categories, items.map { it.category }) }
    val cancel get() = if (lang == "de") "Abbrechen" else "Cancel"
}

val LocalUi = staticCompositionLocalOf<Ui> { error("no Ui") }

/** 'de' or 'en' from the settings, else the phone language. */
fun langOf(s: Settings): String = s.lang?.takeIf { it == "de" || it == "en" } ?: if (Locale.getDefault().language == "en") "en" else "de"

val kindIcon = mapOf("book" to "📖", "game" to "🎲", "dvd" to "📀", "cd" to "💿")

fun toast(context: Context, text: String) = Toast.makeText(context, text, Toast.LENGTH_SHORT).show()

// ---------- dialogs ----------

/** Confirm / prompt / info dialogs that can be awaited from a coroutine. */
class Dialogs {
    class Request(val kind: String, val text: String, val initial: String, val result: CompletableDeferred<String?>)

    var current by mutableStateOf<Request?>(null)
        private set

    private suspend fun show(kind: String, text: String, initial: String = ""): String? {
        val r = Request(kind, text, initial, CompletableDeferred())
        current = r
        try {
            return r.result.await()
        } finally {
            if (current === r) current = null
        }
    }

    suspend fun confirm(text: String) = show("confirm", text) != null

    suspend fun prompt(text: String, initial: String = "") = show("prompt", text, initial)

    suspend fun info(text: String) {
        show("info", text)
    }
}

@Composable
fun DialogHost(dialogs: Dialogs) {
    val ui = LocalUi.current
    val r = dialogs.current ?: return
    var input by remember(r) { mutableStateOf(r.initial) }
    AlertDialog(
        onDismissRequest = { r.result.complete(null) },
        text = {
            if (r.kind == "prompt") {
                OutlinedTextField(value = input, onValueChange = { input = it }, label = { Text(r.text) }, singleLine = true, modifier = Modifier.fillMaxWidth())
            } else {
                Text(r.text)
            }
        },
        confirmButton = {
            Button(onClick = { r.result.complete(if (r.kind == "prompt") input else "") }) { Text(ui.t("ok")) }
        },
        dismissButton = {
            if (r.kind != "info") TextButton(onClick = { r.result.complete(null) }) { Text(ui.cancel) }
        },
    )
}

// ---------- covers ----------

private val coverCache = LruCache<String, ImageBitmap>(64)

/** Decoded own cover photo (data URL), cached so lists scroll smoothly. */
fun coverBitmap(dataUrl: String?): ImageBitmap? {
    if (dataUrl == null) return null
    coverCache.get(dataUrl)?.let { return it }
    return try {
        val bytes = Base64.getDecoder().decode(dataUrl.substring(dataUrl.indexOf(',') + 1))
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap()?.also { coverCache.put(dataUrl, it) }
    } catch (_: Exception) {
        null
    }
}

private fun hsl(h: Float, s: Float, l: Float): Color {
    val c = (1 - kotlin.math.abs(2 * l - 1)) * s
    val x = c * (1 - kotlin.math.abs((h / 60f) % 2 - 1))
    val m = l - c / 2
    val (r, g, b) = when {
        h < 60 -> Triple(c, x, 0f)
        h < 120 -> Triple(x, c, 0f)
        h < 180 -> Triple(0f, c, x)
        h < 240 -> Triple(0f, x, c)
        h < 300 -> Triple(x, 0f, c)
        else -> Triple(c, 0f, x)
    }
    return Color((r + m).coerceIn(0f, 1f), (g + m).coerceIn(0f, 1f), (b + m).coerceIn(0f, 1f))
}

/** Cover image with a coloured placeholder showing the kind (and title when large). */
@Composable
fun CoverImage(title: String, kind: String, coverUrl: String?, coverData: String? = null, large: Boolean = false) {
    val bmp = remember(coverData) { coverBitmap(coverData) }
    val hue = remember(title) { title.fold(0) { h, c -> (h * 31 + c.code) % 360 } }
    Box(
        Modifier.size(if (large) 110.dp else 44.dp, if (large) 160.dp else 64.dp).clip(RoundedCornerShape(4.dp)).background(hsl(hue.toFloat(), 0.45f, 0.55f)),
        contentAlignment = Alignment.Center,
    ) {
        Column(Modifier.padding(6.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(kindIcon[kind] ?: "📖", fontSize = if (large) 20.sp else 16.sp)
            if (large) {
                Spacer(Modifier.height(6.dp))
                Text(title, maxLines = 5, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center, color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
            }
        }
        if (bmp != null) {
            Image(bitmap = bmp, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.matchParentSize())
        } else if (coverUrl != null) {
            // while loading or on error the placeholder underneath stays visible
            AsyncImage(model = coverUrl, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.matchParentSize())
        }
    }
}

@Composable
fun CoverImage(item: Item, large: Boolean = false) = CoverImage(item.title, item.kind, item.coverUrl, item.coverData, large)

// ---------- small widgets ----------

@Composable
fun Stars(value: Int, onChange: ((Int) -> Unit)? = null, small: Boolean = false) {
    val on = Amber700
    val off = MaterialTheme.colorScheme.outlineVariant
    if (onChange == null) {
        if (value == 0) return
        Text(buildAnnotatedString {
            withStyle(SpanStyle(color = on)) { append("★".repeat(value)) }
            withStyle(SpanStyle(color = off)) { append("★".repeat(5 - value)) }
        }, fontSize = if (small) 12.sp else 16.sp)
        return
    }
    val ui = LocalUi.current
    Row {
        for (n in 1..5) {
            Text(
                "★",
                fontSize = 30.sp,
                color = if (n <= value) on else off,
                modifier = Modifier.clip(CircleShape).clickable { onChange(if (value == n) 0 else n) }
                    .semantics { contentDescription = ui.t("rating.n", "n" to n) }.padding(2.dp),
            )
        }
    }
}

/** Small rounded label (status, format, wishlist …). */
@Composable
fun Pill(text: String, color: Color? = null, outlined: Boolean = false) {
    val cs = MaterialTheme.colorScheme
    val shape = RoundedCornerShape(99.dp)
    val m = if (outlined) Modifier.border(1.dp, cs.outlineVariant, shape) else Modifier.background(color ?: cs.surfaceVariant, shape)
    Text(
        text,
        fontSize = 11.sp,
        color = if (outlined) cs.onSurfaceVariant else if (color != null) Color.Black.copy(alpha = 0.87f) else cs.onSurfaceVariant,
        modifier = m.padding(horizontal = 7.dp, vertical = 1.dp),
    )
}

/** One row in the library list; [selected] is non-null in selection mode. */
@Composable
fun ItemTile(item: Item, onClick: () -> Unit, selected: Boolean? = null, onLongClick: (() -> Unit)? = null) {
    val ui = LocalUi.current
    val cs = MaterialTheme.colorScheme
    val i = item
    val loan = i.openLoan
    Row(
        Modifier.fillMaxWidth()
            .combinedClickable(onClick = onClick, onLongClick = onLongClick)
            .background(if (selected == true) cs.primaryContainer.copy(alpha = 0.4f) else Color.Transparent)
            .padding(horizontal = 12.dp, vertical = 8.dp),
    ) {
        if (selected != null) {
            Icon(
                if (selected) Icons.Filled.CheckBox else Icons.Filled.CheckBoxOutlineBlank,
                contentDescription = null,
                tint = cs.primary,
                modifier = Modifier.padding(top = 18.dp, end = 4.dp),
            )
        }
        CoverImage(i)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(buildAnnotatedString {
                append(i.title)
                if (i.volume != null) withStyle(SpanStyle(color = cs.onSurfaceVariant, fontWeight = FontWeight.Normal)) { append(" · ${i.volume}") }
            }, fontWeight = FontWeight.SemiBold)
            if (i.creators.isNotEmpty()) Text(i.creators.joinToString(", "), color = cs.onSurfaceVariant, fontSize = 13.sp)
            Spacer(Modifier.height(3.dp))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                if (i.rating > 0) Stars(i.rating, small = true)
                if (i.status != "none") Pill(ui.t("status.${i.kind}.${i.status}"), if (i.status == "done") cs.secondaryContainer else cs.tertiaryContainer)
                if (i.format != "physical") Pill(ui.t("format.${i.format}"))
                if (!i.owned) Pill(ui.t("scope.wish"), Pink100.copy(alpha = 0.6f))
                i.category?.let { Pill(ui.catLabel(it), outlined = true) }
                if (i.recommend) Text("👍", fontSize = 12.sp)
                if (loan != null) Pill("↗ ${loan.to}", DeepPurple100.copy(alpha = 0.6f))
                if (i.needsCheck) Pill("?", Amber200)
                i.room?.let { Text(it, fontSize = 11.sp, color = cs.onSurfaceVariant) }
            }
        }
    }
}

/** A dropdown entry; headers are shown but can't be picked. */
class Opt<T>(val value: T, val label: String, val header: Boolean = false, val indent: Boolean = false)

/** Read-only text field that opens a menu of [options]. */
@Composable
fun <T> Dropdown(label: String, value: T, options: List<Opt<T>>, onChange: (T) -> Unit, modifier: Modifier = Modifier) {
    var open by remember { mutableStateOf(false) }
    val shown = options.firstOrNull { !it.header && it.value == value }?.label ?: ""
    Box(modifier) {
        OutlinedTextField(
            value = shown,
            onValueChange = {},
            readOnly = true,
            singleLine = true,
            label = { Text(label, maxLines = 1, overflow = TextOverflow.Ellipsis) },
            trailingIcon = { Icon(Icons.Filled.ArrowDropDown, contentDescription = null) },
            modifier = Modifier.fillMaxWidth(),
        )
        Box(Modifier.matchParentSize().clickable { open = true })
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            for (o in options) {
                if (o.header) {
                    DropdownMenuItem(
                        text = { Text(o.label, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary) },
                        onClick = {},
                        enabled = false,
                    )
                } else {
                    DropdownMenuItem(
                        text = { Text(o.label, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = if (o.indent) Modifier.padding(start = 10.dp) else Modifier) },
                        onClick = {
                            open = false
                            onChange(o.value)
                        },
                    )
                }
            }
        }
    }
}

/**
 * Category picker grouped like the default list; own categories come last.
 * [extra] adds entries before the list (e.g. "unchanged" / "all").
 */
@Composable
fun CategoryDropdown(value: String, onChange: (String) -> Unit, extra: List<Opt<String>> = emptyList(), noneValue: String = "", label: String? = null, modifier: Modifier = Modifier) {
    val ui = LocalUi.current
    val cats = ui.categories
    val grouped = defaultCategoryGroups.flatMap { g -> g.items.map { it[0] } }.toSet()
    val options = buildList {
        addAll(extra)
        add(Opt(noneValue, ui.t("cat.none")))
        for (g in defaultCategoryGroups) {
            val ids = g.items.map { it[0] }.filter { it in cats }
            if (ids.isEmpty()) continue
            add(Opt("\u0000${g.de}", if (ui.lang == "de") g.de else g.en, header = true))
            ids.forEach { add(Opt(it, ui.catLabel(it), indent = true)) }
        }
        val own = cats.filter { it !in grouped }
        if (own.isNotEmpty()) {
            add(Opt("\u0000own", ui.t("cat.own"), header = true))
            own.forEach { add(Opt(it, it, indent = true)) }
        }
    }
    val known = options.any { !it.header && it.value == value }
    Dropdown(label ?: ui.t("field.category"), if (known) value else noneValue, options, onChange, modifier.fillMaxWidth())
}

/** Text field with suggestions (rooms, people). Starts with [value]; reports every change. */
@Composable
fun SuggestField(value: String, options: List<String>, label: String, onChange: (String) -> Unit, modifier: Modifier = Modifier) {
    var text by remember { mutableStateOf(value) }
    var open by remember { mutableStateOf(false) }
    val matches = options.filter { it.lowercase().contains(text.lowercase()) && it != text }
    Box(modifier.fillMaxWidth()) {
        OutlinedTextField(
            value = text,
            onValueChange = {
                text = it
                open = true
                onChange(it)
            },
            label = { Text(label) },
            singleLine = true,
            trailingIcon = { IconButton(onClick = { open = !open }) { Icon(Icons.Filled.ArrowDropDown, contentDescription = null) } },
            modifier = Modifier.fillMaxWidth().onFocusChanged { if (it.isFocused) open = true },
        )
        DropdownMenu(expanded = open && matches.isNotEmpty(), onDismissRequest = { open = false }, properties = PopupProperties(focusable = false)) {
            for (o in matches) {
                DropdownMenuItem(text = { Text(o) }, onClick = {
                    text = o
                    open = false
                    onChange(o)
                })
            }
        }
    }
}

/** Single-choice segmented buttons without the check icon. */
@Composable
fun <T> Segmented(options: List<Pair<T, String>>, selected: T, onSelect: (T) -> Unit, modifier: Modifier = Modifier) {
    SingleChoiceSegmentedButtonRow(modifier.fillMaxWidth()) {
        options.forEachIndexed { i, (v, label) ->
            SegmentedButton(
                selected = v == selected,
                onClick = { onSelect(v) },
                shape = SegmentedButtonDefaults.itemShape(index = i, count = options.size),
                icon = {},
                label = { Text(label, maxLines = 2, textAlign = TextAlign.Center, style = MaterialTheme.typography.labelMedium) },
            )
        }
    }
}

/** A label with a switch on the right (Flutter's SwitchListTile). */
@Composable
fun SwitchRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().clickable { onChange(!checked) }.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

/** Amber hint box. */
@Composable
fun HintCard(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(modifier.fillMaxWidth().background(Amber100, RoundedCornerShape(12.dp)).padding(12.dp)) { content() }
}

@Composable
fun Small(text: String, modifier: Modifier = Modifier) =
    Text(text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = modifier)

@Composable
fun Heading(text: String) = Text(text, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
