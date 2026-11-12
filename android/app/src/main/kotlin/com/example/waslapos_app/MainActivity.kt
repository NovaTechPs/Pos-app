package com.example.waslapos_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var bluetoothPrint: BluetoothPrintBridge

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bluetoothPrint = BluetoothPrintBridge(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "waslapos/bluetooth_print")
            .setMethodCallHandler(bluetoothPrint::handle)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (::bluetoothPrint.isInitialized) bluetoothPrint.permissionResult(requestCode, grantResults)
    }

    override fun onDestroy() {
        if (::bluetoothPrint.isInitialized) bluetoothPrint.close()
        super.onDestroy()
    }
}
