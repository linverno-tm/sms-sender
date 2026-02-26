package com.example.sms

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "sms_native"
    private val repository by lazy { BulkSmsRepository(applicationContext) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startBulkSend" -> {
                        val args = call.arguments as? Map<*, *>
                        val message = args?.get("message") as? String
                        val rawNumbers = args?.get("numbers") as? List<*>
                        val numbers = rawNumbers?.mapNotNull { it as? String } ?: emptyList()

                        if (message.isNullOrBlank() || numbers.isEmpty()) {
                            result.error("INVALID_ARGS", "message ёки numbers бўш", null)
                            return@setMethodCallHandler
                        }

                        BulkSmsForegroundService.start(
                            context = applicationContext,
                            message = message,
                            numbers = ArrayList(numbers),
                        )
                        result.success(true)
                    }

                    "stopBulkSend" -> {
                        BulkSmsForegroundService.stop(applicationContext)
                        result.success(true)
                    }

                    "getBulkStatus" -> {
                        val status = repository.getStatus()
                        result.success(status.toMap())
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        repository.close()
        super.onDestroy()
    }
}
