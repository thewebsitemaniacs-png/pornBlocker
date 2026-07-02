package com.habitbreaker.habit_breaker

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
import java.util.HashMap

class BlockerAccessibilityService : AccessibilityService() {

    companion object {
        private var instance: BlockerAccessibilityService? = null
        private var blockedKeywords: List<String> = listOf("shorts", "reels", "doomscroll", "porn", "adult", "xxx")
        private var onBlockedCallback: ((String) -> Unit)? = null

        fun setBlocklist(keywords: List<String>) {
            blockedKeywords = keywords.map { it.lowercase() }
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

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        val appPackage = event.packageName?.toString() ?: return

        // Bypass completely if excluded app, launcher, or our own app
        if (appPackage == packageName || 
            appPackage == launcherPackageName || 
            EXCLUDED_PACKAGES.contains(appPackage)) {
            return
        }

        // Scan windows content changes or state updates
        val source = rootInActiveWindow ?: return
        checkNodeAndChildren(source, appPackage)
    }

    override fun onInterrupt() {
        // No-op
    }

    private fun checkNodeAndChildren(node: AccessibilityNodeInfo, appPackage: String) {
        val text = node.text?.toString()?.lowercase()
        val contentDesc = node.contentDescription?.toString()?.lowercase()

        // Match node text or content description
        if (text != null && matchesBlocklist(text)) {
            handleBlockOrWarning(text, appPackage)
            return
        }
        if (contentDesc != null && matchesBlocklist(contentDesc)) {
            handleBlockOrWarning(contentDesc, appPackage)
            return
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
            Toast.makeText(this, "Content blocked by Curb Habit", Toast.LENGTH_SHORT).show()
        }

        // Notify app layer via event callbacks
        onBlockedCallback?.invoke("Accessibility blocked matching content: $matchedText")
    }
}
