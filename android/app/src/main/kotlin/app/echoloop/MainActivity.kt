package app.echoloop

import android.content.Intent
import android.os.Build
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import android.util.Log
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var googleServicesChannel: MethodChannel? = null
    private var appUpdateChannel: MethodChannel? = null
    private var deviceInfoChannel: MethodChannel? = null
    private var speechPracticeHandler: AndroidSpeechPracticeHandler? = null
    private var audioDecodeHandler: AndroidAudioDecodeHandler? = null
    private var localAudioPicker: AndroidLocalAudioPicker? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.i("AuthGMS", "register google services availability channel")
        googleServicesChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "top.echo-loop/google_services",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "isGooglePlayServicesAvailable" -> result.success(isGooglePlayServicesAvailable())
                    else -> result.notImplemented()
                }
            }
        }
        appUpdateChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "top.echo-loop/app_update",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInstallerPackageName" -> result.success(installerPackageName())
                    else -> result.notImplemented()
                }
            }
        }
        deviceInfoChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "top.echo-loop/device_info",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDeviceInfo" -> result.success(deviceInfo())
                    else -> result.notImplemented()
                }
            }
        }
        speechPracticeHandler = AndroidSpeechPracticeHandler(
            this, flutterEngine.dartExecutor.binaryMessenger,
        )
        audioDecodeHandler = AndroidAudioDecodeHandler(
            flutterEngine.dartExecutor.binaryMessenger,
        )
        localAudioPicker = AndroidLocalAudioPicker(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        googleServicesChannel?.setMethodCallHandler(null)
        googleServicesChannel = null
        appUpdateChannel?.setMethodCallHandler(null)
        appUpdateChannel = null
        deviceInfoChannel?.setMethodCallHandler(null)
        deviceInfoChannel = null
        speechPracticeHandler?.dispose()
        speechPracticeHandler = null
        audioDecodeHandler?.dispose()
        audioDecodeHandler = null
        localAudioPicker?.dispose()
        localAudioPicker = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        // 本地音频选择器消费掉自己的请求码，其余一律继续交给插件体系分发。
        if (localAudioPicker?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        speechPracticeHandler?.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    private fun isGooglePlayServicesAvailable(): Boolean {
        val status = GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(this)
        val available = status == ConnectionResult.SUCCESS
        Log.i("AuthGMS", "Google Play services status=${statusName(status)}($status) available=$available")
        return available
    }

    private fun statusName(status: Int): String {
        return when (status) {
            ConnectionResult.SUCCESS -> "SUCCESS"
            ConnectionResult.SERVICE_MISSING -> "SERVICE_MISSING"
            ConnectionResult.SERVICE_VERSION_UPDATE_REQUIRED -> "SERVICE_VERSION_UPDATE_REQUIRED"
            ConnectionResult.SERVICE_DISABLED -> "SERVICE_DISABLED"
            ConnectionResult.SERVICE_INVALID -> "SERVICE_INVALID"
            else -> "UNKNOWN"
        }
    }

    private fun installerPackageName(): String? {
        return try {
            val installer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                packageManager.getInstallSourceInfo(packageName).installingPackageName
            } else {
                @Suppress("DEPRECATION")
                packageManager.getInstallerPackageName(packageName)
            }
            Log.i("AppUpdate", "installerPackageName=${installer ?: "(null)"}")
            installer
        } catch (e: Exception) {
            Log.w("AppUpdate", "installer source failed", e)
            null
        }
    }

    private fun deviceInfo(): Map<String, Any?> {
        return mapOf(
            "manufacturer" to Build.MANUFACTURER,
            "brand" to Build.BRAND,
            "model" to Build.MODEL,
            "device" to Build.DEVICE,
            "product" to Build.PRODUCT,
            "androidRelease" to Build.VERSION.RELEASE,
            "sdkInt" to Build.VERSION.SDK_INT,
            "supportedAbis" to Build.SUPPORTED_ABIS.toList(),
        )
    }
}
