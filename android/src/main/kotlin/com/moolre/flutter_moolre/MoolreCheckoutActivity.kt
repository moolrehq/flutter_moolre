package com.moolre.flutter_moolre

import android.annotation.SuppressLint
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.Toolbar
import java.net.URISyntaxException

/**
 * Shows Moolre's hosted payment page in the platform WebView and closes when
 * the page navigates to the return URL. The result is only a hint; the Dart
 * side always confirms payment with Moolre's status API.
 */
class MoolreCheckoutActivity : Activity() {
    private var webView: WebView? = null
    private var returnUrl = ""
    private var finished = false

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val url = intent.getStringExtra(EXTRA_URL)
        val ret = intent.getStringExtra(EXTRA_RETURN_URL)
        if (url == null || ret == null) {
            finishWith(EVENT_CLOSED)
            return
        }
        returnUrl = ret

        // An in-layout toolbar instead of the window action bar: on Android 15
        // (edge-to-edge) the action bar overlapped the top of the page.
        val toolbar = Toolbar(this)
        toolbar.title = intent.getStringExtra(EXTRA_TITLE) ?: "Moolre checkout"
        toolbar.setTitleTextColor(Color.WHITE)
        toolbar.navigationIcon = getDrawable(android.R.drawable.ic_menu_close_clear_cancel)
            ?.mutate()
            ?.apply { setTint(Color.WHITE) }
        toolbar.navigationContentDescription = "Close"
        toolbar.setNavigationOnClickListener { finishWith(EVENT_CLOSED) }

        val progress = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal)
        progress.max = 100
        val web = WebView(this)
        web.settings.javaScriptEnabled = true
        web.settings.domStorageEnabled = true
        web.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView, newProgress: Int) {
                progress.progress = newProgress
                progress.visibility = if (newProgress >= 100) View.GONE else View.VISIBLE
            }
        }
        web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(
                view: WebView,
                request: WebResourceRequest,
            ): Boolean = intercept(request.url)

            @Deprecated("Used before API 24")
            override fun shouldOverrideUrlLoading(view: WebView, url: String): Boolean =
                intercept(Uri.parse(url))

            override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
                // Catches redirects that do not pass through shouldOverrideUrlLoading.
                if (isReturnUrl(url)) {
                    view.stopLoading()
                    finishWith(EVENT_REDIRECTED)
                }
            }
        }
        webView = web

        web.setBackgroundColor(Color.WHITE)
        val layout = LinearLayout(this)
        layout.orientation = LinearLayout.VERTICAL
        // Pads for the status bar, navigation bar and keyboard on every API level;
        // the status bar area shows the toolbar colour behind it.
        layout.fitsSystemWindows = true
        layout.setBackgroundColor(TOOLBAR_COLOR)
        toolbar.setBackgroundColor(TOOLBAR_COLOR)
        layout.addView(
            toolbar,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ),
        )
        layout.addView(
            progress,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ),
        )
        layout.addView(
            web,
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f),
        )
        setContentView(layout)
        if (savedInstanceState == null || web.restoreState(savedInstanceState) == null) {
            web.loadUrl(url)
        }
    }

    private fun isReturnUrl(url: String) = url.startsWith(returnUrl)

    /** Returns true when the WebView must not load [uri] itself. */
    private fun intercept(uri: Uri): Boolean {
        if (isReturnUrl(uri.toString())) {
            finishWith(EVENT_REDIRECTED)
            return true
        }
        if (uri.scheme == "https" || uri.scheme == "http") return false
        // tel:, mailto: and wallet-app links open outside the page.
        try {
            val intent = if (uri.scheme == "intent") {
                Intent.parseUri(uri.toString(), Intent.URI_INTENT_SCHEME).apply {
                    addCategory(Intent.CATEGORY_BROWSABLE)
                    component = null
                    selector = null
                }
            } else {
                Intent(Intent.ACTION_VIEW, uri)
            }
            startActivity(intent)
        } catch (_: ActivityNotFoundException) {
        } catch (_: URISyntaxException) {
        }
        return true
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        webView?.saveState(outState)
    }

    @Deprecated("Deprecated in Android 13; still called without a back callback.")
    override fun onBackPressed() {
        val web = webView
        if (web != null && web.canGoBack()) {
            web.goBack()
        } else {
            finishWith(EVENT_CLOSED)
        }
    }

    private fun finishWith(event: String) {
        if (finished) return
        finished = true
        setResult(RESULT_OK, Intent().putExtra(EXTRA_EVENT, event))
        finish()
    }

    override fun onDestroy() {
        webView?.let {
            it.stopLoading()
            (it.parent as? ViewGroup)?.removeView(it)
            it.destroy()
        }
        webView = null
        super.onDestroy()
    }

    companion object {
        const val EXTRA_URL = "com.moolre.flutter_moolre.URL"
        const val EXTRA_RETURN_URL = "com.moolre.flutter_moolre.RETURN_URL"
        const val EXTRA_TITLE = "com.moolre.flutter_moolre.TITLE"
        const val EXTRA_EVENT = "com.moolre.flutter_moolre.EVENT"
        const val EVENT_REDIRECTED = "redirected"
        const val EVENT_CLOSED = "closed"
        private const val TOOLBAR_COLOR = 0xFF142A4A.toInt()
    }
}
