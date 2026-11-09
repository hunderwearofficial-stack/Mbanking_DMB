package com.example.m_banking_bpr

import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.bprdmb.mbanking/device_info"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getHardwareDeviceId") {
                try {
                    val androidId = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID) ?: "UNKNOWN"
                    val brand = (Build.MANUFACTURER ?: "ANDROID").uppercase().replace(" ", "")
                    val model = (Build.MODEL ?: "DEVICE").uppercase().replace(" ", "-")
                    val shortId = if (androidId.length > 8) androidId.takeLast(8).uppercase() else androidId.uppercase()
                    val deviceIdentifier = if (model.startsWith(brand)) {
                        "$model-$shortId"
                    } else {
                        "$brand-$model-$shortId"
                    }
                    result.success(deviceIdentifier)
                } catch (e: Exception) {
                    result.error("DEVICE_ID_ERROR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}

