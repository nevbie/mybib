@file:OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)

package app.mybib.ui

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.viewModelScope
import app.mybib.Screen
import app.mybib.core.Candidate
import app.mybib.core.Draft
import app.mybib.core.Item
import app.mybib.core.classifyCode
import app.mybib.core.draftOf
import app.mybib.core.findDuplicate
import app.mybib.core.numberText
import app.mybib.core.string
import com.google.mlkit.vision.barcode.BarcodeScanner
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import kotlinx.coroutines.launch
import java.util.concurrent.Executors

class ScanState {
    var mode by mutableStateOf("own")

    /** scan / busy / found / none */
    var phase by mutableStateOf("scan")
    var code by mutableStateOf("")
    var found by mutableStateOf(emptyList<Candidate>())
    var dup by mutableStateOf<Item?>(null)
    val added = mutableStateListOf<Item>()
    var room by mutableStateOf<String?>(null)
    var manual by mutableStateOf("")
    var last = ""
}

/** Barcode scanning: add to shelf, add to wishlist, or just check "do I own this?". */
@Composable
fun ScanScreen(screen: Screen.Scan) {
    val ui = LocalUi.current
    val vm = ui.vm
    val ctx = LocalContext.current
    val haptics = LocalHapticFeedback.current
    val st = screen.keep("scan") { ScanState() }
    val room = st.room ?: ui.settings.lastRoom

    fun handle(raw: String) {
        val c = classifyCode(raw)
        if (c == null) {
            toast(ctx, ui.t("scan.invalid"))
            return
        }
        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
        st.phase = "busy"
        st.code = c.code
        // runs in the view model so it finishes even when an entry is opened meanwhile
        vm.viewModelScope.launch {
            val items = vm.store.items.value
            val d0 = items.firstOrNull { it.isbn == c.code }
            val list = if (c.type == "isbn") listOfNotNull(vm.lookup.lookupIsbn(c.code, vm.store.settings.value.googleBooksKey)) else vm.lookup.lookupEan(c.code)
            st.found = list
            st.dup = d0 ?: list.firstOrNull()?.let { findDuplicate(items, title = it.title, creators = it.creators) }
            st.phase = if (list.isNotEmpty()) "found" else "none"
        }
    }

    fun add(c: Candidate) {
        val r = room
        val item = vm.store.addItems(listOf(c.data + draftOf("owned" to (st.mode != "wish"), "room" to (if (st.mode == "wish" || r.isEmpty()) null else r), "source" to "isbn"))).first()
        vm.store.updateSettings { it.copy(lastRoom = r) }
        st.added.add(0, item)
        st.phase = "scan"
    }

    fun edit(data: Draft) {
        vm.push(Screen.Form(draft = data + draftOf("owned" to (st.mode != "wish"), "room" to room.ifEmpty { null }, "source" to "isbn")))
        st.phase = "scan"
    }

    val showResult = st.phase == "found" || st.phase == "none"
    SubScreen(ui.t("scan.title")) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Segmented(listOf("own", "wish", "check").map { it to ui.t("scan.mode.$it") }, st.mode, { st.mode = it })
            if (st.mode == "own") SuggestField(room, ui.rooms, ui.t("field.room"), { st.room = it.trim() })
            BarcodeCamera(
                onCode = { v ->
                    // need the same reading twice in a row to avoid misreads
                    if (st.phase == "scan" && classifyCode(v) != null) {
                        if (v == st.last) {
                            st.last = ""
                            handle(v)
                        } else {
                            st.last = v
                        }
                    }
                },
                modifier = Modifier.fillMaxWidth().aspectRatio(4f / 3f).clip(RoundedCornerShape(14.dp)),
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(
                    st.manual, { st.manual = it },
                    label = { Text(ui.t("scan.manual")) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = { handle(st.manual) }),
                    modifier = Modifier.weight(1f),
                )
                Spacer(Modifier.width(8.dp))
                Button(onClick = { handle(st.manual) }) { Text(ui.t("ok")) }
            }
            if (st.phase == "busy") Text(ui.t("scan.looking", "code" to st.code), Modifier.padding(12.dp))
            val dup = st.dup
            if (showResult && dup != null) {
                HintCard {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            (if (st.mode == "check") "✅ " else "⚠︎ ") + ui.t("scan.have", "title" to dup.title, "place" to (dup.room ?: "–")),
                            color = Color.Black.copy(alpha = 0.87f),
                            modifier = Modifier.weight(1f),
                        )
                        TextButton(onClick = { vm.push(Screen.Detail(dup.id)) }) { Text(ui.t("scan.open")) }
                    }
                }
            }
            if (showResult && st.mode == "check" && dup == null) {
                Card(Modifier.fillMaxWidth()) { Text("❌ ${ui.t("scan.notHave")}", Modifier.padding(16.dp)) }
            }
            if (st.phase == "found") {
                for (c in st.found) {
                    Card(Modifier.fillMaxWidth()) {
                        Row(Modifier.padding(12.dp)) {
                            CoverImage(c.title, c.kind, c.coverUrl, large = true)
                            Spacer(Modifier.width(12.dp))
                            Column(Modifier.weight(1f)) {
                                Text(c.title, fontWeight = FontWeight.Bold)
                                c.data["subtitle"].string?.let { Text(it) }
                                Text(c.creators.joinToString(", "))
                                Small(listOfNotNull(c.data["publisher"].string, c.data["year"].numberText, c.via).joinToString(" · "))
                                if (st.mode != "check") {
                                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                        Button(onClick = { add(c) }) { Text("＋ " + if (st.mode == "wish") ui.t("scan.addWish") else ui.t("scan.add")) }
                                        OutlinedButton(onClick = { edit(c.data) }) { Text(ui.t("scan.edit")) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            if (st.phase == "none") {
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp)) {
                        Text(ui.t("scan.notFound", "code" to st.code))
                        if (st.mode != "check") {
                            TextButton(onClick = { edit(draftOf("title" to "", "isbn" to st.code, "kind" to (if (st.code.startsWith("97")) "book" else "dvd"))) }) {
                                Text(ui.t("scan.manualAdd"))
                            }
                        }
                    }
                }
            }
            if (showResult) TextButton(onClick = { st.phase = "scan" }) { Text(ui.t("scan.next")) }
            if (st.added.isNotEmpty()) {
                Spacer(Modifier.height(10.dp))
                Text(ui.t("scan.added", "n" to st.added.size), fontWeight = FontWeight.Bold)
                for (i in st.added) Text("• ${i.title}")
            }
        }
    }
}

/** Camera preview reading EAN-13/8 and UPC-A/E with ML Kit (bundled model). */
@Composable
fun BarcodeCamera(onCode: (String) -> Unit, modifier: Modifier = Modifier) {
    val ui = LocalUi.current
    val ctx = LocalContext.current
    val owner = LocalLifecycleOwner.current
    val latest by rememberUpdatedState(onCode)
    var granted by remember { mutableStateOf(ContextCompat.checkSelfPermission(ctx, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) }
    var failed by remember { mutableStateOf(false) }
    val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        granted = it
        failed = !it
    }
    LaunchedEffect(Unit) { if (!granted) ask.launch(Manifest.permission.CAMERA) }
    val previewView = remember { PreviewView(ctx).apply { scaleType = PreviewView.ScaleType.FILL_CENTER } }

    DisposableEffect(granted, owner) {
        if (!granted) return@DisposableEffect onDispose {}
        val executor = Executors.newSingleThreadExecutor()
        val scanner = BarcodeScanning.getClient(
            BarcodeScannerOptions.Builder().setBarcodeFormats(Barcode.FORMAT_EAN_13, Barcode.FORMAT_EAN_8, Barcode.FORMAT_UPC_A, Barcode.FORMAT_UPC_E).build(),
        )
        val future = ProcessCameraProvider.getInstance(ctx)
        var provider: ProcessCameraProvider? = null
        var disposed = false
        future.addListener({
            if (disposed) return@addListener
            try {
                val p = future.get()
                provider = p
                val preview = Preview.Builder().build().also { it.setSurfaceProvider(previewView.surfaceProvider) }
                val analysis = ImageAnalysis.Builder().setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST).build()
                analysis.setAnalyzer(executor) { proxy -> analyze(scanner, proxy) { latest(it) } }
                p.unbindAll()
                p.bindToLifecycle(owner, CameraSelector.DEFAULT_BACK_CAMERA, preview, analysis)
            } catch (_: Exception) {
                failed = true
            }
        }, ContextCompat.getMainExecutor(ctx))
        onDispose {
            disposed = true
            provider?.unbindAll()
            scanner.close()
            executor.shutdown()
        }
    }

    Box(modifier.background(Color.Black), contentAlignment = Alignment.Center) {
        if (granted && !failed) {
            AndroidView(factory = { previewView }, modifier = Modifier.fillMaxSize())
            Box(Modifier.fillMaxWidth().padding(horizontal = 40.dp).height(2.dp).background(Color(0xFFFF5252)))
        } else if (failed) {
            Text(ui.t("scan.unsupported"), color = Color.White, textAlign = TextAlign.Center, modifier = Modifier.padding(16.dp))
        }
    }
}

@androidx.annotation.OptIn(ExperimentalGetImage::class)
private fun analyze(scanner: BarcodeScanner, proxy: ImageProxy, onCode: (String) -> Unit) {
    val media = proxy.image
    if (media == null) {
        proxy.close()
        return
    }
    scanner.process(InputImage.fromMediaImage(media, proxy.imageInfo.rotationDegrees))
        .addOnSuccessListener { codes -> codes.firstNotNullOfOrNull { it.rawValue }?.let(onCode) }
        .addOnCompleteListener { proxy.close() }
}
