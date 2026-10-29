package app.liubai.liubai_diary

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.URL
import java.net.Proxy
import javax.net.ssl.HttpsURLConnection

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "liubai/native_network").setMethodCallHandler { call, result ->
            if (call.method != "request") { result.notImplemented(); return@setMethodCallHandler }
            val urlText = call.argument<String>("url") ?: ""
            val method = call.argument<String>("method") ?: "GET"
            val headers = call.argument<Map<String,String>>("headers") ?: emptyMap()
            val body = call.argument<ByteArray>("body") ?: byteArrayOf()
            Thread {
                var connection: HttpsURLConnection? = null
                try {
                    val url = URL(urlText)
                    require(url.protocol == "https") { "HTTPS required" }
                    connection = url.openConnection(Proxy.NO_PROXY) as HttpsURLConnection
                    val c = connection!!
                    c.connectTimeout = 15000
                    c.readTimeout = 20000
                    c.instanceFollowRedirects = false
                    c.requestMethod = method
                    c.useCaches = false
                    headers.forEach { (name,value) -> c.setRequestProperty(name,value) }
                    if (body.isNotEmpty()) {
                        c.doOutput = true
                        c.setFixedLengthStreamingMode(body.size)
                        c.outputStream.use { it.write(body) }
                    }
                    val status = c.responseCode
                    val stream = if(status >= 400) c.errorStream else c.inputStream
                    val bytes = stream?.use { it.readBytes() } ?: byteArrayOf()
                    runOnUiThread { result.success(mapOf("status" to status, "body" to bytes)) }
                } catch (e: Exception) {
                    // Only error type/message, never request headers, passwords or tokens.
                    val detail = "${e.javaClass.simpleName}: ${e.message ?: "network failed"}"
                    runOnUiThread { result.error("DIRECT_NETWORK", detail, null) }
                } finally { connection?.disconnect() }
            }.start()
        }
    }
}
