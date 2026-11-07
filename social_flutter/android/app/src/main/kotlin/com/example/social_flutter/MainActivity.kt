package com.example.social_flutter

import android.content.pm.ActivityInfo
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // A phone is portrait-only from the launch screen on, before Dart can
        // say so; a tablet (sw600dp and up) turns freely. The manifest cannot
        // tell them apart (lib/core/ui/orientation_policy.dart is the Dart side).
        if (resources.configuration.smallestScreenWidthDp < 600) {
            requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        }
        super.onCreate(savedInstanceState)
    }

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
