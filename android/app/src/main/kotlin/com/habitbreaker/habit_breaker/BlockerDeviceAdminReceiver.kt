package com.habitbreaker.habit_breaker

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
import android.widget.Toast

class BlockerDeviceAdminReceiver : DeviceAdminReceiver() {

    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
        Toast.makeText(context, "Curb Habit Uninstall Guard Activated", Toast.LENGTH_SHORT).show()
    }

    override fun onDisableRequested(context: Context, intent: Intent): CharSequence? {
        // This is called when the user attempts to deactivate device admin.
        // Returning a message displays a warning dialog and prompts the security warning.
        // We will hook this into our bypass delay timers inside Flutter.
        return "Warning: Deactivating Curb Habit Uninstall Guard will disable bypass timers and expose your device to distractions. A delay timer may be active."
    }

    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)
        Toast.makeText(context, "Uninstall Guard Deactivated", Toast.LENGTH_SHORT).show()
    }
}
