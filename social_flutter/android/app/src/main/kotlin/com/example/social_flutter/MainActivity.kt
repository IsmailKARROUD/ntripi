package com.example.social_flutter

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The share popup with a Copy link row, which share_plus cannot add
        // (lib/features/itineraries/data/share_service.dart is the Dart side).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ntripi/share")
            .setMethodCallHandler { call, result ->
                if (call.method != "share") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                ShareLinkChooser.show(
                    this,
                    text = call.argument<String>("text") ?: "",
                    url = call.argument<String>("url") ?: "",
                    subject = call.argument<String>("subject"),
                    copyLinkLabel = call.argument<String>("copyLinkLabel") ?: "",
                    copiedLabel = call.argument<String>("copiedLabel") ?: "",
                )
                result.success(null)
            }
    }
}
