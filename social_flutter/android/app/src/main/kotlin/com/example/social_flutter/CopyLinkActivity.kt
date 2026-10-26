package com.example.social_flutter

import android.app.Activity
import android.os.Build
import android.os.Bundle
import android.widget.Toast

// The share popup's Copy link row before Android 14, whose popup takes no
// actions of its own (ShareLinkChooser): a target that copies and is gone.
// Translucent and finished at once, so the screen never changes.
class CopyLinkActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val url = intent.getStringExtra(ShareLinkChooser.EXTRA_LINK)
        if (url != null) {
            ShareLinkChooser.copy(this, url)
            // Android 13 confirms a copy itself; older versions say nothing.
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                intent.getStringExtra(ShareLinkChooser.EXTRA_COPIED)?.let {
                    Toast.makeText(this, it, Toast.LENGTH_SHORT).show()
                }
            }
        }
        finish()
    }
}
