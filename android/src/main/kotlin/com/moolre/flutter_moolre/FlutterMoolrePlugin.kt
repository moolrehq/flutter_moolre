package com.moolre.flutter_moolre

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/** Opens Moolre's hosted payment page in [MoolreCheckoutActivity]. */
class FlutterMoolrePlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    PluginRegistry.ActivityResultListener {
    private var channel: MethodChannel? = null
    private var binding: ActivityPluginBinding? = null
    private var pending: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        this.binding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        binding?.removeActivityResultListener(this)
        binding = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "open") {
            result.notImplemented()
            return
        }
        val activity = binding?.activity
        val url = call.argument<String>("url")
        val returnUrl = call.argument<String>("returnUrl")
        when {
            activity == null ->
                result.error("NO_ACTIVITY", "Checkout needs a foreground activity.", null)
            url == null || returnUrl == null || !url.startsWith("https://") ->
                result.error("INVALID_ARGUMENTS", "A secure checkout URL is required.", null)
            pending != null ->
                result.error("ALREADY_OPEN", "Checkout is already open.", null)
            else -> {
                pending = result
                val intent = Intent(activity, MoolreCheckoutActivity::class.java)
                    .putExtra(MoolreCheckoutActivity.EXTRA_URL, url)
                    .putExtra(MoolreCheckoutActivity.EXTRA_RETURN_URL, returnUrl)
                    .putExtra(MoolreCheckoutActivity.EXTRA_TITLE, call.argument<String>("title"))
                activity.startActivityForResult(intent, REQUEST_CODE)
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val event = if (resultCode == Activity.RESULT_OK) {
            data?.getStringExtra(MoolreCheckoutActivity.EXTRA_EVENT)
        } else {
            null
        }
        pending?.success(mapOf("event" to (event ?: MoolreCheckoutActivity.EVENT_CLOSED)))
        pending = null
        return true
    }

    private companion object {
        const val CHANNEL = "flutter_moolre/hosted_checkout"
        const val REQUEST_CODE = 0x4D4F
    }
}
