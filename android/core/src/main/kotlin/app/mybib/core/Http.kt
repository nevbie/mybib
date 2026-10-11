package app.mybib.core

import java.net.HttpURLConnection
import java.net.URL

class HttpRequest(
    val method: String,
    val url: String,
    val headers: Map<String, String> = emptyMap(),
    val body: ByteArray? = null,
    val timeoutMs: Int = 12_000,
)

/** Header names are lower-case. */
class HttpResponse(val status: Int, val headers: Map<String, String> = emptyMap(), val body: ByteArray = ByteArray(0)) {
    val text get() = body.decodeToString()
}

/** The little HTTP the app needs; blocking, swappable for tests. */
fun interface Http {
    fun send(req: HttpRequest): HttpResponse
}

/** Default implementation, works on the JVM and on Android. */
class UrlConnectionHttp : Http {
    override fun send(req: HttpRequest): HttpResponse {
        val c = URL(req.url).openConnection() as HttpURLConnection
        try {
            c.requestMethod = req.method
            c.connectTimeout = req.timeoutMs
            c.readTimeout = req.timeoutMs
            c.instanceFollowRedirects = true
            req.headers.forEach { (k, v) -> c.setRequestProperty(k, v) }
            if (req.body != null) {
                c.doOutput = true
                c.setFixedLengthStreamingMode(req.body.size)
                c.outputStream.use { it.write(req.body) }
            }
            val status = c.responseCode
            val headers = c.headerFields.entries.filter { it.key != null }.associate { (k, v) -> k.lowercase() to v.joinToString(", ") }
            val stream = if (status >= 400) c.errorStream else c.inputStream
            val body = if (req.method == "HEAD") ByteArray(0) else stream?.use { it.readBytes() } ?: ByteArray(0)
            return HttpResponse(status, headers, body)
        } finally {
            c.disconnect()
        }
    }
}
