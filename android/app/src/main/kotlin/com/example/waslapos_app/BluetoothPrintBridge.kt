package com.example.waslapos_app

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.pdf.PdfRenderer
import android.os.Build
import android.os.ParcelFileDescriptor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.ByteArrayOutputStream
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.ceil
import kotlin.math.min

/** Paired Bluetooth Classic ESC/POS printers; Arabic is rendered from the existing PDF. */
class BluetoothPrintBridge(private val activity: Activity) {
    private val builtIn = Q6PrinterBridge(activity)
    private val worker = Executors.newSingleThreadExecutor()
    private val deadlines = Executors.newSingleThreadScheduledExecutor()
    private var pendingPermission: Pair<MethodCall, MethodChannel.Result>? = null
    @Volatile private var socket: BluetoothSocket? = null

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "builtInAvailable") {
            result.success(builtIn.available()); return
        }
        if (call.method == "printBuiltIn") {
            worker.execute {
                try {
                    builtIn.print(call.argument<ByteArray>("bytes") ?: error("الفاتورة فارغة."))
                    activity.runOnUiThread { result.success(null) }
                } catch (error: Exception) {
                    activity.runOnUiThread { result.error("q6_print", error.message, null) }
                }
            }
            return
        }
        if (call.method !in listOf("pairedDevices", "printPdf")) {
            result.notImplemented(); return
        }
        val missingBluetoothPermissions = if (Build.VERSION.SDK_INT >= 31) {
            arrayOf(Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_SCAN)
                .filter { activity.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
                .toTypedArray()
        } else emptyArray()
        if (missingBluetoothPermissions.isNotEmpty()) {
            if (pendingPermission != null) {
                result.error("busy", "انتظر الموافقة على إذن البلوتوث.", null); return
            }
            pendingPermission = Pair(call, result)
            activity.requestPermissions(missingBluetoothPermissions, 8431)
            return
        }
        execute(call, result)
    }

    fun permissionResult(code: Int, grants: IntArray) {
        if (code != 8431) return
        val pending = pendingPermission ?: return
        pendingPermission = null
        if (grants.isNotEmpty() && grants.all { it == PackageManager.PERMISSION_GRANTED }) execute(pending.first, pending.second)
        else pending.second.error("permission", "اسمح للتطبيق بالاتصال بأجهزة البلوتوث من إعدادات الأذونات.", null)
    }

    @Suppress("MissingPermission")
    private fun execute(call: MethodCall, result: MethodChannel.Result) {
        worker.execute task@{
            var started = false
            try {
                val adapter = activity.getSystemService(BluetoothManager::class.java)?.adapter
                    ?: error("هذا الجهاز لا يدعم البلوتوث.")
                check(adapter.isEnabled) { "شغّل البلوتوث ثم أعد المحاولة." }
                if (call.method == "pairedDevices") {
                    val devices = adapter.bondedDevices.sortedBy { it.name ?: it.address }.map {
                        mapOf("name" to (it.name ?: it.address), "address" to it.address)
                    }
                    activity.runOnUiThread { result.success(devices) }
                    return@task
                }
                val address = call.argument<String>("address") ?: error("اختر الطابعة أولاً.")
                val bytes = call.argument<ByteArray>("bytes") ?: error("الفاتورة فارغة.")
                val width = call.argument<Number>("width")?.toInt() ?: 384
                require(width == 384 || width == 576)
                val device = adapter.bondedDevices.firstOrNull { it.address == address }
                    ?: error("الطابعة غير مقترنة. اقترن بها من إعدادات بلوتوث الجهاز.")
                val spp = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
                adapter.cancelDiscovery()
                val connection = device.createRfcommSocketToServiceRecord(spp)
                socket = connection
                val expired = AtomicBoolean(false)
                val timeout = deadlines.schedule({
                    expired.set(true)
                    try { socket?.close() } catch (_: Exception) {}
                }, 90, TimeUnit.SECONDS)
                try {
                    var activeConnection: BluetoothSocket? = null
                    var secureError: Exception? = null
                    val connectTimeout = deadlines.schedule({ try { connection.close() } catch (_: Exception) {} }, 12, TimeUnit.SECONDS)
                    try {
                        connection.connect()
                        activeConnection = connection
                    } catch (error: Exception) {
                        secureError = error
                        try { connection.close() } catch (_: Exception) {}
                        if (expired.get()) throw error
                        val fallback = device.createInsecureRfcommSocketToServiceRecord(spp)
                        socket = fallback
                        val fallbackTimeout = deadlines.schedule({ try { fallback.close() } catch (_: Exception) {} }, 12, TimeUnit.SECONDS)
                        try {
                            fallback.connect()
                            activeConnection = fallback
                        } catch (fallbackError: Exception) {
                            try { fallback.close() } catch (_: Exception) {}
                            throw IllegalStateException(
                                "فشل الاتصال الآمن وغير الآمن. أعد إقران الطابعة وتأكد أنها ESC/POS Bluetooth Classic. السبب: ${fallbackError.message ?: fallbackError.javaClass.simpleName}",
                                secureError,
                            )
                        } finally { fallbackTimeout.cancel(false) }
                    } finally { connectTimeout.cancel(false) }
                    checkNotNull(activeConnection).use { connected ->
                        socket = connected
                        val file = File.createTempFile("receipt-", ".pdf", activity.cacheDir)
                        try {
                            file.writeBytes(bytes)
                            ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
                                PdfRenderer(descriptor).use { renderer ->
                                    val out = connected.outputStream
                                    out.write(byteArrayOf(0x1b, 0x40))
                                    for (index in 0 until renderer.pageCount) {
                                        renderer.openPage(index).use { page ->
                                            val scale = width.toFloat() / page.width
                                            val height = ceil(page.height * scale).toInt()
                                            // Render bounded strips rather than allocating a long receipt bitmap.
                                            var y = 0
                                            while (y < height) {
                                                val rows = min(128, height - y)
                                                val bitmap = Bitmap.createBitmap(width, rows, Bitmap.Config.ARGB_8888)
                                                try {
                                                    bitmap.eraseColor(Color.WHITE)
                                                    val matrix = Matrix().apply { setScale(scale, scale); postTranslate(0f, -y.toFloat()) }
                                                    page.render(bitmap, null, matrix, PdfRenderer.Page.RENDER_MODE_FOR_PRINT)
                                                    val pixels = IntArray(width * rows)
                                                    val strip = ByteArrayOutputStream()
                                                    bitmap.getPixels(pixels, 0, width, 0, 0, width, rows)
                                                    // Send complete raster strips, including their white rows.
                                                    // ESC J feed units vary by printer and can stretch gaps.
                                                    val rowBytes = width / 8
                                                    strip.write(byteArrayOf(0x1d, 0x76, 0x30, 0,
                                                        (rowBytes and 0xff).toByte(), (rowBytes shr 8).toByte(),
                                                        (rows and 0xff).toByte(), (rows shr 8).toByte()))
                                                    val data = ByteArray(rowBytes * rows)
                                                    for (row in 0 until rows) {
                                                        for (x in 0 until width) {
                                                            val pixel = pixels[row * width + x]
                                                            if ((Color.red(pixel) * 299 + Color.green(pixel) * 587 + Color.blue(pixel) * 114) < 160000) {
                                                                val position = row * rowBytes + x / 8
                                                                data[position] = (data[position].toInt() or (0x80 shr (x % 8))).toByte()
                                                            }
                                                        }
                                                    }
                                                    strip.write(data)
                                                    val packet = strip.toByteArray()
                                                    var offset = 0
                                                    while (offset < packet.size) {
                                                        started = true
                                                        val count = min(1024, packet.size - offset)
                                                        out.write(packet, offset, count)
                                                        offset += count
                                                        Thread.sleep(2)
                                                    }
                                                    out.flush()
                                                    // Small pause lets portable printer buffers drain.
                                                    Thread.sleep(12)
                                                } finally { bitmap.recycle() }
                                                y += rows
                                            }
                                        }
                                    }
                                    out.write(byteArrayOf(0x1b, 0x64, 3))
                                    out.flush()
                                }
                            }
                        } finally { file.delete() }
                    }
                    check(!expired.get()) { "انتهت مهلة الإرسال." }
                } finally { timeout.cancel(false); socket = null }
                activity.runOnUiThread { result.success(null) }
            } catch (error: Exception) {
                val message = if (started) "قد تكون الفاتورة طُبعت جزئياً. تحقق من الورق قبل إعادة الطباعة. ${error.message ?: ""}"
                    else "تعذر الاتصال بالطابعة. شغّلها، أوقف اقترانها بجهاز آخر، ثم أعد إقرانها واخترها من إعدادات الطابعات. يجب أن تدعم ESC/POS Bluetooth Classic. السبب: ${error.message ?: error.javaClass.simpleName}"
                activity.runOnUiThread { result.error("bluetooth_print", message, null) }
            }
        }
    }

    fun close() {
        try { socket?.close() } catch (_: Exception) {}
        pendingPermission?.second?.error("closed", "أُغلقت شاشة الطباعة.", null)
        pendingPermission = null
        worker.shutdownNow()
        deadlines.shutdownNow()
    }
}
