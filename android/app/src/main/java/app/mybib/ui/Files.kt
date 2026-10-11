package app.mybib.ui

import android.Manifest
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import app.mybib.core.parseImportFile
import app.mybib.core.toCSV
import app.mybib.core.toExport
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.File
import java.time.LocalDate
import java.util.Base64

private fun authority(ctx: Context) = "${ctx.packageName}.files"

/** Load a photo, turn it upright and downscale it to [maxEdge] px as JPEG. Null when unreadable. Blocking. */
fun loadJpeg(ctx: Context, uri: Uri, maxEdge: Int, quality: Int): ByteArray? = try {
    val cr = ctx.contentResolver
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    cr.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
    var sample = 1
    while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxEdge) sample *= 2
    val bmp = cr.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample }) }
    if (bmp == null) {
        null
    } else {
        val rotation = cr.openInputStream(uri)?.use {
            when (ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90
                ExifInterface.ORIENTATION_ROTATE_180 -> 180
                ExifInterface.ORIENTATION_ROTATE_270 -> 270
                else -> 0
            }
        } ?: 0
        val scale = minOf(1f, maxEdge.toFloat() / maxOf(bmp.width, bmp.height))
        val out = if (scale < 1f || rotation != 0) {
            val m = Matrix().apply {
                postScale(scale, scale)
                postRotate(rotation.toFloat())
            }
            Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, m, true)
        } else {
            bmp
        }
        ByteArrayOutputStream().use { s ->
            out.compress(Bitmap.CompressFormat.JPEG, quality, s)
            s.toByteArray()
        }
    }
} catch (_: Exception) {
    null
}

fun dataUrl(jpeg: ByteArray) = "data:image/jpeg;base64,${Base64.getEncoder().encodeToString(jpeg)}"

/** Small cover thumbnail kept with the item (≈ 20–40 KB), as data URL like the web app. */
fun coverDataUrl(ctx: Context, uri: Uri): String? = loadJpeg(ctx, uri, 480, 80)?.let(::dataUrl)

class PhotoPicker(val camera: () -> Unit, val gallery: () -> Unit)

/** Camera (asks for the permission first) and gallery picker; [onPicked] gets the photo URIs. */
@Composable
fun rememberPhotoPicker(multiple: Boolean = false, onPicked: (List<Uri>) -> Unit): PhotoPicker {
    val ctx = LocalContext.current
    val latest by rememberUpdatedState(onPicked)
    var pending by rememberSaveable { mutableStateOf<Uri?>(null) }
    val take = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { ok ->
        val u = pending
        if (ok && u != null) latest(listOf(u))
    }
    fun launchCamera() {
        val dir = File(ctx.cacheDir, "photos").apply { mkdirs() }
        val u = FileProvider.getUriForFile(ctx, authority(ctx), File.createTempFile("photo", ".jpg", dir))
        pending = u
        take.launch(u)
    }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted -> if (granted) launchCamera() }
    val one = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { u -> if (u != null) latest(listOf(u)) }
    val many = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia()) { us -> if (us.isNotEmpty()) latest(us) }
    return PhotoPicker(
        camera = {
            if (ContextCompat.checkSelfPermission(ctx, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) launchCamera()
            else permission.launch(Manifest.permission.CAMERA)
        },
        gallery = {
            val req = PickVisualMediaRequest(mediaType = ActivityResultContracts.PickVisualMedia.ImageOnly)
            if (multiple) many.launch(req) else one.launch(req)
        },
    )
}

// ---------- share, export, import ----------

fun shareText(ctx: Context, text: String, subject: String) {
    val i = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_TEXT, text)
        putExtra(Intent.EXTRA_SUBJECT, subject)
    }
    ctx.startActivity(Intent.createChooser(i, null))
}

fun shareFile(ctx: Context, name: String, text: String, mime: String) {
    val dir = File(ctx.cacheDir, "share").apply { mkdirs() }
    val f = File(dir, name).apply { writeText(text) }
    val uri = FileProvider.getUriForFile(ctx, authority(ctx), f)
    val i = Intent(Intent.ACTION_SEND).apply {
        type = mime
        putExtra(Intent.EXTRA_STREAM, uri)
        clipData = ClipData.newRawUri(name, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    ctx.startActivity(Intent.createChooser(i, null))
}

fun stamp() = LocalDate.now().toString()

fun exportJson(ui: Ui) = toExport(ui.store.items.value).toString()

fun exportCsv(ui: Ui) = toCSV(ui.store.items.value)

/** Save the JSON backup to a file the user picks (Storage Access Framework). */
@Composable
fun rememberJsonExporter(): () -> Unit {
    val ui = LocalUi.current
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val latest by rememberUpdatedState(ui)
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        if (uri != null) scope.launch {
            val ok = withContext(Dispatchers.IO) {
                try {
                    ctx.contentResolver.openOutputStream(uri)?.use { it.write(exportJson(latest).encodeToByteArray()) } != null
                } catch (_: Exception) {
                    false
                }
            }
            if (ok) toast(ctx, latest.t("data.saved"))
        }
    }
    return { launcher.launch("mybib-${stamp()}.json") }
}

/** Pick a JSON file (backup, Claude import or update file) and merge it into the catalogue. */
@Composable
fun rememberImporter(): () -> Unit {
    val ui = LocalUi.current
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val latest by rememberUpdatedState(ui)
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) scope.launch {
            val u = latest
            val msg = try {
                val text = withContext(Dispatchers.IO) { ctx.contentResolver.openInputStream(uri)!!.use { it.readBytes().decodeToString() } }
                val f = parseImportFile(text)
                val r = u.store.importItems(f.items, f.updateOnly)
                u.t("data.imported", "added" to r.added, "updated" to r.updated, "skipped" to r.skipped)
            } catch (e: Exception) {
                if (e is CancellationException) throw e
                u.t("data.importError", "e" to (e.message ?: e.toString()))
            }
            u.vm.dialogs.info(msg)
        }
    }
    return { launcher.launch(arrayOf("*/*")) }
}
