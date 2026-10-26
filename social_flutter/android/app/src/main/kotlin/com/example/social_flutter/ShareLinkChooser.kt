package com.example.social_flutter

import android.app.Activity
import android.app.PendingIntent
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.LabeledIntent
import android.graphics.drawable.Icon
import android.os.Build
import android.service.chooser.ChooserAction

// The phone's own share popup for a shared trip or profile, with one row
// added: Copy link, which copies the link alone. Other apps — and the popup's
// own Copy — still get the caption and the link.
object ShareLinkChooser {
    const val EXTRA_LINK = "ntripi.share.link"
    const val EXTRA_COPIED = "ntripi.share.copied"

    fun show(
        activity: Activity,
        text: String,
        url: String,
        subject: String?,
        copyLinkLabel: String,
        copiedLabel: String,
    ) {
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
            if (!subject.isNullOrEmpty()) putExtra(Intent.EXTRA_SUBJECT, subject)
        }
        val chooser = Intent.createChooser(send, null)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // Android 14+: an action of the popup's own, beside its Copy. The
            // system confirms the copy itself.
            val copy = PendingIntent.getBroadcast(
                activity,
                0,
                Intent(activity, CopyLinkReceiver::class.java).putExtra(EXTRA_LINK, url),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val action = ChooserAction.Builder(
                Icon.createWithResource(activity, R.drawable.ic_copy_link),
                copyLinkLabel,
                copy,
            ).build()
            chooser.putExtra(Intent.EXTRA_CHOOSER_CUSTOM_ACTIONS, arrayOf(action))
        } else {
            // Older popups take no actions: the row is the first target instead.
            val copy = Intent(activity, CopyLinkActivity::class.java)
                .putExtra(EXTRA_LINK, url)
                .putExtra(EXTRA_COPIED, copiedLabel)
            chooser.putExtra(
                Intent.EXTRA_INITIAL_INTENTS,
                arrayOf(LabeledIntent(copy, activity.packageName, copyLinkLabel, R.drawable.ic_copy_link)),
            )
        }
        activity.startActivity(chooser)
    }

    fun copy(context: Context, url: String) {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("Ntripi", url))
    }
}
