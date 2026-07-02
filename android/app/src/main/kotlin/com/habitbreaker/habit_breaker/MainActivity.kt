package com.habitbreaker.habit_breaker

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import android.os.Handler
import android.os.Looper
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import java.util.HashMap

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.habitbreaker.app/blocking"
    private val EVENT_CHANNEL = "com.habitbreaker.app/blocking_events"
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val adminComponent = ComponentName(this, BlockerDeviceAdminReceiver::class.java)
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager

        // MethodChannel handler
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkPermissions" -> {
                    val isAccessibilityActive = BlockerAccessibilityService.isRunning()
                    val isVpnActive = VpnService.prepare(this) == null
                    val isAdminActive = dpm.isAdminActive(adminComponent)
                    
                    val permissions = HashMap<String, Boolean>()
                    permissions["accessibility"] = isAccessibilityActive
                    permissions["vpn"] = isVpnActive
                    permissions["admin"] = isAdminActive
                    
                    result.success(permissions)
                }
                "requestPermissions" -> {
                    val type = call.argument<String>("type")
                    try {
                        when (type) {
                            "accessibility" -> {
                                val intent = Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS)
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                                result.success(true)
                            }
                            "vpn" -> {
                                val vpnIntent = VpnService.prepare(this)
                                if (vpnIntent != null) {
                                    startActivityForResult(vpnIntent, 102)
                                    result.success(true)
                                } else {
                                    result.success(true) // Already authorized
                                }
                            }
                            "admin" -> {
                                val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
                                intent.putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, adminComponent)
                                intent.putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION, "Enable Uninstall Guard to prevent weak-moment bypasses.")
                                startActivity(intent)
                                result.success(true)
                            }
                            else -> result.error("INVALID_TYPE", "Permission request type not supported: $type", null)
                        }
                    } catch (e: Exception) {
                        result.error("FAILED", e.message, null)
                    }
                }
                "startBlocking" -> {
                    // Start VPN service
                    try {
                        val intent = Intent(this, BlockerVpnService::class.java)
                        startService(intent)
                        triggerMockBlockingEvent("VPN blocking service started.")
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("VPN_START_FAILED", e.message, null)
                    }
                }
                "stopBlocking" -> {
                    // Stop VPN service
                    try {
                        BlockerVpnService.stopVpn()
                        triggerMockBlockingEvent("VPN blocking service stopped.")
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("VPN_STOP_FAILED", e.message, null)
                    }
                }
                "updateBlocklist" -> {
                    val domains = call.argument<List<String>>("domains") ?: emptyList()
                    val keywords = call.argument<List<String>>("keywords") ?: emptyList()
                    
                    BlockerAccessibilityService.setBlocklist(keywords)
                    BlockerVpnService.setBlocklist(domains)
                    
                    triggerMockBlockingEvent("Blocklists updated: ${domains.size} domains, ${keywords.size} keywords.")
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // EventChannel handler
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    
                    // Register Accessibility blocker callback to forward alerts directly to Flutter EventChannel
                    BlockerAccessibilityService.registerCallback { matchedContent ->
                        val event = HashMap<String, Any>()
                        event["type"] = "accessibility_block"
                        event["message"] = matchedContent
                        event["timestamp"] = System.currentTimeMillis()
                        
                        Handler(Looper.getMainLooper()).post {
                            eventSink?.success(event)
                        }
                    }
                    
                    triggerMockBlockingEvent("Android Native Blocker bound to event channel.")
                }

                override fun onCancel(arguments: Any?) {
                    BlockerAccessibilityService.unregisterCallback()
                    eventSink = null
                }
            }
        )
    }

    private fun triggerMockBlockingEvent(message: String) {
        Handler(Looper.getMainLooper()).post {
            val event = HashMap<String, Any>()
            event["type"] = "native_log"
            event["message"] = message
            event["timestamp"] = System.currentTimeMillis()
            eventSink?.success(event)
        }
    }
}
