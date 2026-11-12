package com.example.waslapos_app

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.pdf.PdfRenderer
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.ParcelFileDescriptor
import com.iposprinter.iposprinterservice.IPosPrinterCallback
import com.iposprinter.iposprinterservice.IPosPrinterService
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.ceil
import kotlin.math.min

/** Optional Q6 Pro iPos service, discovered rather than assumed from model name. */
class Q6PrinterBridge(private val activity: Activity) {
    private val main = Handler(Looper.getMainLooper())
    private fun intent() = Intent("com.iposprinter.iposprinterservice.IPosPrintService")
        .setPackage("com.iposprinter.iposprinterservice")

    fun available(): Boolean = activity.packageManager.resolveService(intent(), 0) != null

    fun print(bytes: ByteArray) {
        check(available()) { "خدمة طابعة Q6 الداخلية غير متاحة على هذا الجهاز." }
        val service = AtomicReference<IPosPrinterService?>()
        val ready = CountDownLatch(1)
        val bound = AtomicBoolean(false)
        val abandoned = AtomicBoolean(false)
        val connection = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName, binder: IBinder) {
                service.set(IPosPrinterService.Stub.asInterface(binder)); ready.countDown()
            }
            override fun onServiceDisconnected(name: ComponentName) { service.set(null) }
            override fun onNullBinding(name: ComponentName) { ready.countDown() }
            override fun onBindingDied(name: ComponentName) { ready.countDown() }
        }
        main.post {
            if (!abandoned.get()) {
                try { bound.set(activity.bindService(intent(), connection, Context.BIND_AUTO_CREATE)) }
                catch (_: Exception) { ready.countDown() }
                if (!bound.get()) ready.countDown()
            }
        }
        var submitted = false
        try {
            check(ready.await(10, TimeUnit.SECONDS)) { "انتهت مهلة الاتصال بالطابعة المدمجة." }
            val printer = service.get() ?: error("تعذر تشغيل خدمة الطابعة المدمجة.")
            val status = printer.getPrinterStatus()
            check(status == 0) {
                when(status) {
                    1 -> "ضع ورقاً في الطابعة ثم أعد المحاولة."
                    2, 3 -> "الطابعة ساخنة؛ انتظر حتى تبرد."
                    4 -> "الطابعة مشغولة؛ انتظر انتهاء المهمة الحالية."
                    else -> "الطابعة غير جاهزة (الحالة $status)."
                }
            }
            val callback = object : IPosPrinterCallback.Stub() {
                override fun onRunResult(success: Boolean) {}
                override fun onReturnString(value: String?) {}
            }
            printer.printerInit(callback)
            val file = File.createTempFile("q6-receipt-", ".pdf", activity.cacheDir)
            try {
                file.writeBytes(bytes)
                ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
                    PdfRenderer(descriptor).use { renderer ->
                        for (index in 0 until renderer.pageCount) {
                            renderer.openPage(index).use { page ->
                                val width = 384
                                val scale = width.toFloat() / page.width
                                val height = ceil(page.height * scale).toInt()
                                check(height in 1..20000) { "صفحة الفاتورة طويلة جداً للطابعة المدمجة." }
                                val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                                try {
                                    bitmap.eraseColor(Color.WHITE)
                                    page.render(bitmap, null, Matrix().apply { setScale(scale, scale) }, PdfRenderer.Page.RENDER_MODE_FOR_PRINT)
                                    val row = IntArray(width)
                                    var bottom = height
                                    while (bottom > 0) {
                                        bitmap.getPixels(row, 0, width, 0, bottom - 1, width, 1)
                                        if (row.any { Color.red(it) < 220 || Color.green(it) < 220 || Color.blue(it) < 220 }) break
                                        bottom--
                                    }
                                    var y = 0
                                    while (y < bottom) {
                                        // Stay below Binder transaction limits even for long invoices.
                                        val rows = min(128, bottom - y)
                                        val strip = Bitmap.createBitmap(bitmap, 0, y, width, rows)
                                        try { printer.printBitmap(1, 16, strip, callback) }
                                        finally { if (strip !== bitmap) strip.recycle() }
                                        y += rows
                                    }
                                } finally { bitmap.recycle() }
                            }
                        }
                    }
                }
            } finally { file.delete() }
            val done = CountDownLatch(1)
            val success = AtomicBoolean(false)
            val completed = object : IPosPrinterCallback.Stub() {
                override fun onRunResult(isSuccess: Boolean) { success.set(isSuccess); done.countDown() }
                override fun onReturnString(value: String?) {}
            }
            submitted = true
            printer.printerPerformPrint(80, completed)
            check(done.await(60, TimeUnit.SECONDS) && success.get()) {
                "لم تؤكد خدمة الطابعة اكتمال المهمة."
            }
        } catch (error: Exception) {
            if (submitted) throw IllegalStateException("قد تكون الفاتورة طُبعت. تحقق من الورق قبل إعادة الطباعة. ${error.message}", error)
            throw error
        } finally {
            abandoned.set(true)
            main.post {
                if (bound.get()) try { activity.unbindService(connection) } catch (_: Exception) {}
            }
        }
    }
}
