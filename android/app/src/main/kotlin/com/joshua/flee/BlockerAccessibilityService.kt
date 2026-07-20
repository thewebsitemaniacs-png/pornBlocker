package com.joshua.flee

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.os.Handler
import android.os.Looper
import android.content.Context
import android.graphics.PixelFormat
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import android.graphics.drawable.GradientDrawable
import android.graphics.Typeface
import android.widget.Toast
import android.util.Log
import java.util.HashMap
import java.util.Locale

class BlockerAccessibilityService : AccessibilityService() {

    companion object {
        private var instance: BlockerAccessibilityService? = null
        private var blockedKeywords: List<String> = listOf("hot girls", "fuck", "sex videos", "porn", "adult", "xxx")
        private var onBlockedCallback: ((String) -> Unit)? = null
        private var dynamicExcludedPackages: Set<String> = emptySet()
        private var dynamicTextBoxOnlyPackages: Set<String> = emptySet()
        
        // Static flag to dynamically enable/disable accessibility scanning from app config
        var isScreenBlockingEnabled: Boolean = true

        // Set to true to temporarily disable active blocking and only show test Toast alerts
        var isTestingMode: Boolean = false

        fun setBlocklist(keywords: List<String>) {
            blockedKeywords = keywords.map { it.lowercase() }
            Log.d("BlockerAccessibility", "Active blocklist keywords updated: $blockedKeywords")
        }

        fun setAppBlockingModes(excluded: List<String>, textBoxOnly: List<String>) {
            dynamicExcludedPackages = excluded.toSet()
            dynamicTextBoxOnlyPackages = textBoxOnly.toSet()
        }

        fun registerCallback(callback: (String) -> Unit) {
            onBlockedCallback = callback
        }

        fun unregisterCallback() {
            onBlockedCallback = null
        }
        
        fun isRunning(): Boolean {
            return instance != null
        }
    }

    private val EXCLUDED_PACKAGES = setOf(
        "com.android.settings",
        "com.google.android.dialer",
        "com.android.contacts",
        "com.android.vending",
        "com.google.android.packageinstaller"
    )

    private val BROWSER_PACKAGES = setOf(
        "com.android.chrome",
        "org.mozilla.firefox",
        "com.sec.android.app.sbrowser",
        "com.opera.browser",
        "com.opera.mini.native",
        "com.brave.browser",
        "com.duckduckgo.mobile.android",
        "com.android.browser",
        "com.microsoft.emmx",
        "com.vivaldi.browser",
        "com.kiwibrowser.browser"
    )

    private fun isBrowserApp(packageName: String): String? {
        if (BROWSER_PACKAGES.contains(packageName)) return packageName
        val lower = packageName.lowercase()
        if (lower.contains("browser") || lower.contains("chrome") || lower.contains("firefox") || lower.contains("webview")) {
            return packageName
        }
        return null
    }

    private val WARNING_PACKAGES = setOf(
        "com.whatsapp",
        "org.telegram.messenger",
        "ch.threema.app",
        "org.thoughtcrime.securesms",
        "com.google.android.apps.messaging",
        "com.google.android.gm",
        "com.microsoft.office.outlook"
    )

    private var launcherPackageName: String? = null
    private val lastWarningTimestamps = HashMap<String, Long>()
    private val WARNING_COOLDOWN_MS = 5 * 60 * 1000 // 5 minutes

    private var activeOverlayView: View? = null
    private val handler = Handler(Looper.getMainLooper())

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        try {
            val intent = Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
            }
            val resolveInfo = packageManager.resolveActivity(intent, 0)
            launcherPackageName = resolveInfo?.activityInfo?.packageName
        } catch (e: Exception) {
            // ignore resolving launcher package
        }
    }

    override fun onDestroy() {
        dismissOverlay()
        instance = null
        super.onDestroy()
    }

    private fun isKeyboardApp(packageName: String): Boolean {
        val lower = packageName.lowercase()
        return lower.contains("inputmethod") || 
               lower.contains("keyboard") || 
               lower.contains("ime") || 
               lower.contains("gboard") || 
               lower.contains("swiftkey")
    }

    private fun isExcludedApp(appPackage: String): Boolean {
        val lower = appPackage.lowercase()
        return appPackage == packageName || 
               lower == "com.joshua.flee" ||
               appPackage == launcherPackageName || 
               EXCLUDED_PACKAGES.contains(appPackage) || 
               dynamicExcludedPackages.contains(appPackage) ||
               isKeyboardApp(appPackage)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (!isScreenBlockingEnabled) return
        if (event == null) return

        val appPackage = event.packageName?.toString() ?: return

        // Bypass completely if excluded app or flee app itself
        if (isExcludedApp(appPackage)) {
            return
        }

        // Check active window root to ensure user isn't inside flee app while an input/overlay event fires
        val activeWindowPackage = rootInActiveWindow?.packageName?.toString()
        if (activeWindowPackage != null && isExcludedApp(activeWindowPackage)) {
            return
        }

        // 1. Scan direct event text content (catches keyboard typing inputs instantly)
        val isBrowser = isBrowserApp(appPackage) != null
        if (event.eventType == AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED && !isBrowser) {
            try {
                val eventTextList = event.text
                if (eventTextList != null) {
                    for (t in eventTextList) {
                        val textStr = t?.toString()?.lowercase()
                        if (textStr != null && matchesBlocklist(textStr)) {
                            handleBlockOrWarning(textStr, appPackage)
                            return
                        }
                    }
                }
            } catch (e: Exception) {
                // Ignore event parsing errors
            }
        }

        // 2. Scan direct event node tree context
        val eventSource = event.source
        if (eventSource != null) {
            checkNodeAndChildren(eventSource, appPackage)
        }

        // 3. Scan full window contents (catches rendered/scrolled views in background thread loops)
        val activeWindow = rootInActiveWindow
        if (activeWindow != null) {
            checkNodeAndChildren(activeWindow, appPackage)
        }
    }

    override fun onInterrupt() {
        // No-op
    }

    private fun isNodeInWebView(node: AccessibilityNodeInfo): Boolean {
        var current: AccessibilityNodeInfo? = node
        while (current != null) {
            val className = current.className?.toString()
            if (className != null && (className.contains("WebView") || className.contains("browser.engine"))) {
                return true
            }
            try {
                current = current.parent
            } catch (e: Exception) {
                break
            }
        }
        return false
    }

    private fun checkNodeAndChildren(node: AccessibilityNodeInfo, appPackage: String) {
        val nodePackage = node.packageName?.toString()
        if (nodePackage != null && isExcludedApp(nodePackage)) {
            return
        }

        val isBrowser = isBrowserApp(appPackage) != null
        val isTextBoxOnly = dynamicTextBoxOnlyPackages.contains(appPackage)
        
        val shouldScan = if (isExcludedApp(appPackage)) {
            false
        } else if (isTextBoxOnly) {
            node.isEditable
        } else if (isBrowser) {
            isNodeInWebView(node) // ONLY scan webpage/HTML rendering views, bypassing native address bars and dropdown suggestions
        } else {
            true // Default to full scan for other apps
        }

        if (shouldScan) {
            val text = node.text?.toString()?.lowercase()
            val contentDesc = node.contentDescription?.toString()?.lowercase()

            if (text != null && matchesBlocklist(text)) {
                handleBlockOrWarning(text, appPackage)
                return
            }
            if (contentDesc != null && matchesBlocklist(contentDesc)) {
                handleBlockOrWarning(contentDesc, appPackage)
                return
            }
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i)
            if (child != null) {
                checkNodeAndChildren(child, appPackage)
            }
        }
    }

    private fun matchesBlocklist(content: String): Boolean {
        for (keyword in blockedKeywords) {
            if (content.contains(keyword)) {
                return true
            }
        }
        return false
    }

    private fun handleBlockOrWarning(matchedText: String, appPackage: String) {
        if (isTestingMode) {
            Handler(Looper.getMainLooper()).post {
                Toast.makeText(this, "[TEST MODE] Trigger matched: $matchedText in $appPackage", Toast.LENGTH_LONG).show()
            }
            Log.d("BlockerAccessibility", "[TEST MODE] Trigger matched: $matchedText in $appPackage")
            return
        }

        if (WARNING_PACKAGES.contains(appPackage)) {
            val now = System.currentTimeMillis()
            val lastTime = lastWarningTimestamps[appPackage] ?: 0L
            if (now - lastTime < WARNING_COOLDOWN_MS) {
                return // Within cooldown, bypass
            }
            lastWarningTimestamps[appPackage] = now
            showTriggerWarningOverlay(matchedText)
        } else {
            triggerBlockAction(matchedText)
        }
    }

    private fun showTriggerWarningOverlay(matchedText: String) {
        handler.post {
            if (activeOverlayView != null) return@post

            val windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
            
            // Container layout
            val container = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                setBackgroundColor(0xDD0F0E17.toInt()) // Semi-transparent dark background
                setPadding(48, 48, 48, 48)
                // Consume all touch events so user cannot tap through
                setOnTouchListener { _, _ -> true }
            }

            // Card layout (inner container)
            val card = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER_HORIZONTAL
                setPadding(32, 48, 32, 48)
            }
            
            // Rounded corners and orange border shape programmatically
            val shape = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = 32f
                setColor(0xFF1F1E29.toInt()) // Card background
                setStroke(3, 0xFFFF8906.toInt()) // Orange border
            }
            card.background = shape

            // Title TextView
            val titleView = TextView(this).apply {
                text = "⚠️ TRIGGER WARNING ⚠️"
                textSize = 22f
                setTextColor(0xFFFF8906.toInt())
                gravity = Gravity.CENTER
                setTypeface(null, Typeface.BOLD)
            }
            
            // Message TextView
            val messageView = TextView(this).apply {
                text = "Flagged keyword detected. Let's take a 60-second mindful pause to breathe and reset your focus."
                textSize = 15f
                setTextColor(0xFFFFFFFF.toInt())
                gravity = Gravity.CENTER
                setLineSpacing(0f, 1.3f)
                setPadding(0, 24, 0, 24)
            }

            // Timer TextView
            val timerView = TextView(this).apply {
                text = "Pausing for 60s..."
                textSize = 18f
                setTextColor(0xFFA7A9BE.toInt())
                gravity = Gravity.CENTER
                setTypeface(null, Typeface.BOLD)
            }

            // Assemble card
            card.addView(titleView)
            card.addView(messageView)
            card.addView(timerView)

            // Layout params for card
            val cardParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.CENTER
                leftMargin = 32
                rightMargin = 32
            }
            container.addView(card, cardParams)

            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                PixelFormat.TRANSLUCENT
            )

            try {
                windowManager.addView(container, params)
                activeOverlayView = container

                // Start 60-second countdown
                var secondsLeft = 60
                var runnable: Runnable? = null
                runnable = Runnable {
                    secondsLeft--
                    if (secondsLeft > 0) {
                        timerView.text = "Pausing for ${secondsLeft}s..."
                        handler.postDelayed(runnable!!, 1000)
                    } else {
                        dismissOverlay()
                    }
                }
                handler.postDelayed(runnable, 1000)
                
                // Notify app layer via event callbacks
                onBlockedCallback?.invoke("Accessibility warning triggered matching content: $matchedText")
            } catch (e: Exception) {
                // Fail-safe cleanup
                activeOverlayView = null
            }
        }
    }

    private fun dismissOverlay() {
        handler.post {
            activeOverlayView?.let { view ->
                val windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
                try {
                    windowManager.removeView(view)
                } catch (e: Exception) {
                    // Ignore if already removed
                }
                activeOverlayView = null
            }
        }
    }

    private fun triggerBlockAction(matchedText: String) {
        // Perform back action to pull user out of current view/tab
        performGlobalAction(GLOBAL_ACTION_BACK)

        Handler(Looper.getMainLooper()).post {
            Toast.makeText(this, "Content blocked by flee", Toast.LENGTH_SHORT).show()
        }

        // Notify app layer via event callbacks
        onBlockedCallback?.invoke("Accessibility blocked matching content: $matchedText")
    }
}
