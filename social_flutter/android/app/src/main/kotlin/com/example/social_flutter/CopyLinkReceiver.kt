package com.example.social_flutter

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

// The share popup's Copy link row on Android 14+ (ShareLinkChooser).
class CopyLinkReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val url = intent.getStringExtra(ShareLinkChooser.EXTRA_LINK) ?: return
        ShareLinkChooser.copy(context, url)
    }
}
