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
import app.mybib.core.Store
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

/**
 * Cut one cover out of a photo with several ([box] = x0, y0, x1, y1 in thousandths of width/height, as Claude
 * reports it), with a small margin, as a cover thumbnail data URL. Null when the box is unusable.
 */
fun cropCover(jpeg: ByteArray, box: List<Double>, rotation: Int = 0): String? = try {
    val bmp = BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size)
    fun f(v: Double) = (v / 1000).coerceIn(0.0, 1.0)
    val pad = 0.01
    val x0 = (f(minOf(box[0], box[2])) - pad).coerceAtLeast(0.0)
    val y0 = (f(minOf(box[1], box[3])) - pad).coerceAtLeast(0.0)
    val x1 = (f(maxOf(box[0], box[2])) + pad).coerceAtMost(1.0)
    val y1 = (f(maxOf(box[1], box[3])) + pad).coerceAtMost(1.0)
    val l = (x0 * bmp.width).toInt()
    val t = (y0 * bmp.height).toInt()
    val w = ((x1 - x0) * bmp.width).toInt().coerceAtMost(bmp.width - l)
    val h = ((y1 - y0) * bmp.height).toInt().coerceAtMost(bmp.height - t)
    if (w < 20 || h < 20) {
        null
    } else {
        val scale = minOf(1f, 480f / maxOf(w, h))
        val m = Matrix().apply {
            postScale(scale, scale)
            postRotate(rotation.toFloat())
        }
        val out = Bitmap.createBitmap(bmp, l, t, w, h, m, true)
        ByteArrayOutputStream().use { s ->
            out.compress(Bitmap.CompressFormat.JPEG, 80, s)
            dataUrl(s.toByteArray())
        }
    }
} catch (_: Exception) {
    null
}

/** Turn a cover photo (data URL) clockwise by 90/180/270 degrees. */
fun rotateDataUrl(dataUrl: String, rotation: Int): String {
    if (rotation % 360 == 0) return dataUrl
    return try {
        val bytes = Base64.getDecoder().decode(dataUrl.substring(dataUrl.indexOf(',') + 1))
        val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return dataUrl
        val out = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, Matrix().apply { postRotate(rotation.toFloat()) }, true)
        ByteArrayOutputStream().use { s ->
            out.compress(Bitmap.CompressFormat.JPEG, 85, s)
            dataUrl(s.toByteArray())
        }
    } catch (_: Exception) {
        dataUrl
    }
}

/** The JPEG bytes of a data URL (to send own covers to Claude). */
fun dataUrlBytes(dataUrl: String): ByteArray = Base64.getDecoder().decode(dataUrl.substring(dataUrl.indexOf(',') + 1))

private const val PENDING = "pending_photo"

private fun clearPendingPhoto(ctx: Context) = ctx.getSharedPreferences(PENDING, Context.MODE_PRIVATE).edit().clear().apply()

/**
 * If Android closed the app while the camera was open (low memory), the photo result never arrives.
 * The picker notes what the photo was for ("cover:<item id>"); on the next start this saves it as that cover.
 */
fun applyPendingPhoto(ctx: Context, store: Store) {
    val p = ctx.getSharedPreferences(PENDING, Context.MODE_PRIVATE)
    val key = p.getString("key", null) ?: return
    val path = p.getString("path", null)
    p.edit().clear().apply()
    val file = path?.let(::File) ?: return
    if (!key.startsWith("cover:") || !file.exists() || file.length() == 0L) return
    val id = key.removePrefix("cover:")
    if (store.byId(id) == null) return
    val data = coverDataUrl(ctx, Uri.fromFile(file)) ?: return
    store.updateItem(id, "coverData" to data)
}

class PhotoPicker(val camera: () -> Unit, val gallery: () -> Unit)

/** Camera (asks for the permission first) and gallery picker; [onPicked] gets the photo URIs. */
@Composable
fun rememberPhotoPicker(multiple: Boolean = false, pendingKey: (() -> String?)? = null, onPicked: (List<Uri>) -> Unit): PhotoPicker {
    val ctx = LocalContext.current
    val latest by rememberUpdatedState(onPicked)
    val key by rememberUpdatedState(pendingKey)
    var pending by rememberSaveable { mutableStateOf<Uri?>(null) }
    var pendingPath by rememberSaveable { mutableStateOf<String?>(null) }
    val take = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { ok ->
        val u = pending
        val written = pendingPath?.let { File(it).length() > 0 } ?: false
        clearPendingPhoto(ctx)
        // some camera apps report "cancelled" although they saved the photo
        if (u != null && (ok || written)) latest(listOf(u))
    }
    fun launchCamera() {
        val dir = File(ctx.cacheDir, "photos").apply { mkdirs() }
        val file = File.createTempFile("photo", ".jpg", dir)
        val u = FileProvider.getUriForFile(ctx, authority(ctx), file)
        pending = u
        pendingPath = file.path
        key?.invoke()?.let { k ->
            ctx.getSharedPreferences(PENDING, Context.MODE_PRIVATE).edit().putString("key", k).putString("path", file.path).apply()
        }
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

fun exportJson(ui: Ui) = toExport(ui.store.items.value, ui.store.removed.value).toString()

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
                val r = u.store.importItems(f.items, f.updateOnly, f.removed)
                u.t("data.imported", "added" to r.added, "updated" to r.updated, "skipped" to r.skipped) +
                    (if (r.removed > 0) " " + u.t("data.importRemoved", "n" to r.removed) else "")
            } catch (e: Exception) {
                if (e is CancellationException) throw e
                u.t("data.importError", "e" to (e.message ?: e.toString()))
            }
            u.vm.dialogs.info(msg)
        }
    }
    return { launcher.launch(arrayOf("*/*")) }
}
