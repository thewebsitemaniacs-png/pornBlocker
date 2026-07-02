package com.habitbreaker.habit_breaker

import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.content.Intent
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.InetAddress
import java.nio.ByteBuffer
import android.util.Log

class BlockerVpnService : VpnService(), Runnable {

    companion object {
        private var instance: BlockerVpnService? = null
        private var blockedDomains: List<String> = listOf("youtube.com", "instagram.com", "tiktok.com", "pornhub.com", "xvideos.com")
        private var vpnThread: Thread? = null

        fun setBlocklist(domains: List<String>) {
            blockedDomains = domains.map { it.lowercase() }
        }

        fun isRunning(): Boolean {
            return instance != null
        }

        fun stopVpn() {
            vpnThread?.interrupt()
            instance?.stopSelf()
            instance = null
        }
    }

    private var vpnInterface: ParcelFileDescriptor? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (vpnThread == null || !vpnThread!!.isAlive) {
            vpnThread = Thread(this, "BlockerVpnThread")
            vpnThread!!.start()
        }
        return START_STICKY;
    }

    override fun onDestroy() {
        stopVpn()
        vpnInterface?.close()
        vpnInterface = null
        super.onDestroy()
    }

    override fun run() {
        try {
            // Establish the local virtual network interface routing IPv4 and DNS (8.8.8.8)
            val builder = Builder()
            builder.setSession("Curb Habit Blocker")
                .addAddress("10.0.0.2", 24)
                .addDnsServer("8.8.8.8")
                .addRoute("0.0.0.0", 0) // Route all traffic to inspect DNS packets

            vpnInterface = builder.establish()
            val input = FileInputStream(vpnInterface!!.fileDescriptor)
            val output = FileOutputStream(vpnInterface!!.fileDescriptor)

            val packet = ByteBuffer.allocate(32767)

            while (!Thread.interrupted()) {
                val length = input.read(packet.array())
                if (length > 0) {
                    // In a production routing loop, we parse the IP header and DNS payload.
                    // If a query matches the blockedDomains, resolve DNS to 127.0.0.1 (sinkhole).
                    // For scaffolding & battery performance, we perform basic packet forwarding.
                    packet.limit(length)
                    output.write(packet.array(), 0, length)
                    packet.clear()
                }
                Thread.sleep(10)
            }
        } catch (e: Exception) {
            Log.e("BlockerVpnService", "VPN execution loop interrupted: ${e.message}")
        }
    }
}
