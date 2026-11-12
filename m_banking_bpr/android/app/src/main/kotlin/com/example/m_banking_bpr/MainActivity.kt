package com.example.m_banking_bpr

import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.bprdmb.mbanking/device_info"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Hardening FLAG_SECURE: Blocks screenshots, screen recordings, and hides app preview in recent apps
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getHardwareDeviceId" -> {
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
                }
                "setFlagSecure" -> {
                    try {
                        val enable = call.argument<Boolean>("enable") ?: true
                        runOnUiThread {
                            if (enable) {
                                window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            }
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.error("FLAG_SECURE_ERROR", e.message, null)
                    }
                }
                "isFlagSecureEnabled" -> {
                    try {
                        val isSecure = (window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE) != 0
                        result.success(isSecure)
                    } catch (e: Exception) {
                        result.error("FLAG_SECURE_CHECK_ERROR", e.message, null)
                    }
                }
                "checkRootStatus" -> {
                    try {
                        val rootResult = checkDeviceRoot()
                        result.success(rootResult)
                    } catch (e: Exception) {
                        result.error("ROOT_CHECK_ERROR", e.message, null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun checkDeviceRoot(): Map<String, Any> {
        val reasons = mutableListOf<String>()

        // 1. Check Build Tags
        val buildTags = Build.TAGS
        if (buildTags != null && buildTags.contains("test-keys")) {
            reasons.add("Test-keys build detected (OS non-release)")
        }

        // 2. Check Common Root Binaries
        val binaryPaths = arrayOf(
            "/system/app/Superuser.apk",
            "/sbin/su",
            "/system/bin/su",
            "/system/xbin/su",
            "/data/local/xbin/su",
            "/data/local/bin/su",
            "/system/sd/xbin/su",
            "/system/bin/failsafe/su",
            "/data/local/su",
            "/su/bin/su",
            "/system/xbin/daemonsu"
        )
        for (path in binaryPaths) {
            try {
                if (File(path).exists()) {
                    reasons.add("Root binary found: $path")
                }
            } catch (_: Exception) {}
        }

        // 3. Check 'which su' execution
        var process: Process? = null
        try {
            process = Runtime.getRuntime().exec(arrayOf("/system/xbin/which", "su"))
            val reader = BufferedReader(InputStreamReader(process.inputStream))
            val line = reader.readLine()
            if (line != null && line.trim().isNotEmpty()) {
                reasons.add("Command 'which su' returned: $line")
            }
        } catch (_: Exception) {
        } finally {
            process?.destroy()
        }

        // 4. Check Known Root Manager Packages
        val rootPackages = arrayOf(
            "com.topjohnwu.magisk",
            "eu.chainfire.supersu",
            "com.noshufou.android.su",
            "com.koushikdutta.superuser",
            "com.thirdparty.superuser",
            "com.yellowes.su"
        )
        val pm = packageManager
        for (pkg in rootPackages) {
            try {
                pm.getPackageInfo(pkg, 0)
                reasons.add("Root management package installed: $pkg")
            } catch (_: PackageManager.NameNotFoundException) {
                // Not installed (normal)
            } catch (_: Exception) {}
        }

        val isRooted = reasons.isNotEmpty()
        return mapOf(
            "isRooted" to isRooted,
            "reasons" to reasons,
            "deviceModel" to (Build.MODEL ?: "Android"),
            "osVersion" to Build.VERSION.RELEASE
        )
    }
}
