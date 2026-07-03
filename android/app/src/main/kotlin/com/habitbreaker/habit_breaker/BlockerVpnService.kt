package com.habitbreaker.habit_breaker

import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.content.Intent
import android.util.Log
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.nio.ByteBuffer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class BlockerVpnService : VpnService(), Runnable {

    companion object {
        private var instance: BlockerVpnService? = null
        private var blockedDomains: List<String> = listOf("youtube.com", "instagram.com", "tiktok.com", "pornhub.com", "xvideos.com")
        private var vpnThread: Thread? = null

        fun setBlocklist(domains: List<String>) {
            // Known secure DNS bootstrap domains to block so browsers fall back to system UDP DNS
            val secureDnsBypasses = listOf(
                "dns.google", "cloudflare-dns.com", "chrome.cloudflare-dns.com",
                "dns.quad9.net", "dns.adguard.com", "doh.cleanbrowsing.org",
                "dns.nextdns.io"
            )
            blockedDomains = (domains + secureDnsBypasses).map { it.lowercase() }
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
    private var dnsExecutor: ExecutorService? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        dnsExecutor = Executors.newFixedThreadPool(4)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (vpnThread == null || !vpnThread!!.isAlive) {
            vpnThread = Thread(this, "BlockerVpnThread")
            vpnThread!!.start()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        stopVpn()
        dnsExecutor?.shutdownNow()
        vpnInterface?.close()
        vpnInterface = null
        super.onDestroy()
    }

    override fun run() {
        try {
            // Establish local dual-stack DNS redirect.
            val builder = Builder()
            builder.setSession("Curb Habit Blocker")
                .addAddress("10.0.0.2", 24)
                .addDnsServer("8.8.8.8")
                .addRoute("8.8.8.8", 32)
                .addAddress("fd00:0:0:0:0:0:0:2", 64)
                .addDnsServer("2001:4860:4860::8888")
                .addRoute("2001:4860:4860::8888", 128)

            vpnInterface = builder.establish()
            val input = FileInputStream(vpnInterface!!.fileDescriptor)
            val output = FileOutputStream(vpnInterface!!.fileDescriptor)

            val packetBuffer = ByteArray(32767)

            while (!Thread.interrupted()) {
                val length = input.read(packetBuffer)
                if (length > 0) {
                    if (isDnsPacket(packetBuffer, length)) {
                        val packetCopy = packetBuffer.copyOf(length)
                        dnsExecutor?.submit {
                            processDnsPacket(packetCopy, output)
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.e("BlockerVpnService", "VPN loop error: ${e.message}")
        }
    }

    private fun isDnsPacket(data: ByteArray, length: Int): Boolean {
        if (length < 28) return false // IP (20) + UDP (8)
        
        val version = (data[0].toInt() and 0xF0) shr 4
        if (version == 4) {
            val protocol = data[9].toInt()
            if (protocol != 17) return false // Not UDP
            val destPort = ((data[22].toInt() and 0xFF) shl 8) or (data[23].toInt() and 0xFF)
            return destPort == 53
        } else if (version == 6) {
            if (length < 48) return false // IPv6 (40) + UDP (8)
            val nextHeader = data[6].toInt()
            if (nextHeader != 17) return false // Not UDP
            val destPort = ((data[42].toInt() and 0xFF) shl 8) or (data[43].toInt() and 0xFF)
            return destPort == 53
        }
        return false
    }

    private fun processDnsPacket(data: ByteArray, output: FileOutputStream) {
        try {
            val version = (data[0].toInt() and 0xF0) shr 4
            val dnsOffset = if (version == 4) 28 else 48
            
            val domain = parseDnsQuestion(data, dnsOffset)
            val isBlocked = blockedDomains.any { domain.contains(it) }
            
            if (isBlocked) {
                val response = buildSinkholeResponse(data, version, dnsOffset)
                synchronized(output) {
                    output.write(response)
                }
            } else {
                val udpOffset = if (version == 4) 20 else 40
                val udpLen = ((data[udpOffset + 4].toInt() and 0xFF) shl 8) or (data[udpOffset + 5].toInt() and 0xFF)
                val dnsQueryLen = udpLen - 8
                if (dnsQueryLen <= 0 || dnsOffset + dnsQueryLen > data.size) return
                
                val dnsQuery = data.copyOfRange(dnsOffset, dnsOffset + dnsQueryLen)
                val socket = DatagramSocket()
                protect(socket) // Shield socket from local VPN loopback routing
                socket.soTimeout = 2000
                
                val serverAddr = if (version == 4) {
                    InetAddress.getByName("1.1.1.1") // Forward to Cloudflare (avoid 8.8.8.8 loopback)
                } else {
                    InetAddress.getByName("2606:4700:4700::1111")
                }
                
                val sendPacket = DatagramPacket(dnsQuery, dnsQuery.size, serverAddr, 53)
                socket.send(sendPacket)
                
                val recvBuf = ByteArray(1024)
                val recvPacket = DatagramPacket(recvBuf, recvBuf.size)
                socket.receive(recvPacket)
                
                val dnsResponse = recvBuf.copyOf(recvPacket.length)
                val fullPacket = buildIpUdpPacket(data, dnsResponse, version, dnsOffset)
                
                synchronized(output) {
                    output.write(fullPacket)
                }
                socket.close()
            }
        } catch (e: Exception) {
            // Fail-safe cleanup
        }
    }

    private fun parseDnsQuestion(data: ByteArray, offset: Int): String {
        var current = offset + 12
        val sb = StringBuilder()
        while (current < data.size) {
            val labelLength = data[current].toInt() and 0xFF
            if (labelLength == 0) break
            
            if (sb.isNotEmpty()) sb.append(".")
            for (i in 0 until labelLength) {
                current++
                if (current < data.size) {
                    sb.append(data[current].toChar())
                } else {
                    break
                }
            }
            current++
        }
        return sb.toString().lowercase()
    }

    private fun buildSinkholeResponse(queryPacket: ByteArray, version: Int, dnsOffset: Int): ByteArray {
        val responseBuffer = ByteBuffer.allocate(512)
        
        // Copy transaction ID
        responseBuffer.put(queryPacket[dnsOffset])
        responseBuffer.put(queryPacket[dnsOffset + 1])
        
        // Flags: 0x8180 (Standard Query Response, No Error)
        responseBuffer.put(0x81.toByte())
        responseBuffer.put(0x80.toByte())
        
        // Questions Count: 1
        responseBuffer.put(0x00.toByte())
        responseBuffer.put(0x01.toByte())
        
        // Answer RRs: 1
        responseBuffer.put(0x00.toByte())
        responseBuffer.put(0x01.toByte())
        
        // Authority & Additional RRs: 0
        responseBuffer.put(0x00.toByte())
        responseBuffer.put(0x00.toByte())
        responseBuffer.put(0x00.toByte())
        responseBuffer.put(0x00.toByte())
        
        // Copy Question section
        var current = dnsOffset + 12
        while (current < queryPacket.size) {
            val len = queryPacket[current].toInt() and 0xFF
            responseBuffer.put(queryPacket[current])
            if (len == 0) {
                responseBuffer.put(queryPacket[current + 1])
                responseBuffer.put(queryPacket[current + 2])
                responseBuffer.put(queryPacket[current + 3])
                responseBuffer.put(queryPacket[current + 4])
                break
            }
            for (i in 0 until len) {
                current++
                responseBuffer.put(queryPacket[current])
            }
            current++
        }
        
        // Answer Section: Name (pointer to offset 12 -> 0xc00c)
        responseBuffer.put(0xc0.toByte())
        responseBuffer.put(0x0c.toByte())
        
        if (version == 4) {
            // Type: A (0x0001)
            responseBuffer.put(0x00.toByte())
            responseBuffer.put(0x01.toByte())
            // Class: IN (0x0001)
            responseBuffer.put(0x00.toByte())
            responseBuffer.put(0x01.toByte())
            // TTL: 60s
            responseBuffer.put(0x00.toByte())
            responseBuffer.put(0x00.toByte())
            responseBuffer.put(0x00.toByte())
            responseBuffer.put(0x3c.toByte())
            // Data Length: 4 bytes
            responseBuffer.put(0x00.toByte())
            responseBuffer.put(0x04.toByte())
            // IP: 0.0.0.0
            responseBuffer.put(0x00.toByte())
            responseBuffer.put(0x00.toByte())
            responseBuffer.put(0x00.toByte())
            responseBuffer.put(0x00.toByte())
        } else {
            // Type: AAAA (0x001c)
            responseBuffer.put(0x00.toByte())
            responseBuffer.put(0x1c.toByte())
            // Class: IN (0x0001)
            responseBuffer.put(0x00.toByte())
            responseBuffer.put(0x01.toByte())
            // TTL: 60s
            responseBuffer.put(0x00.toByte())
            responseBuffer.put(0x00.toByte())
            responseBuffer.put(0x00.toByte())
            responseBuffer.put(0x3c.toByte())
            // Data Length: 16 bytes
            responseBuffer.put(0x00.toByte())
            responseBuffer.put(0x10.toByte())
            // IP: :: (16 bytes of 0)
            for (i in 0 until 16) responseBuffer.put(0x00.toByte())
        }
        
        val dnsResponseLen = responseBuffer.position()
        val dnsResponse = ByteArray(dnsResponseLen)
        System.arraycopy(responseBuffer.array(), 0, dnsResponse, 0, dnsResponseLen)
        
        return buildIpUdpPacket(queryPacket, dnsResponse, version, dnsOffset)
    }

    private fun buildIpUdpPacket(queryPacket: ByteArray, dnsPayload: ByteArray, version: Int, dnsOffset: Int): ByteArray {
        val ipHeaderLen = if (version == 4) 20 else 40
        val totalLength = ipHeaderLen + 8 + dnsPayload.size
        val packet = ByteArray(totalLength)
        
        if (version == 4) {
            // --- IPv4 Header ---
            packet[0] = 0x45.toByte()
            packet[1] = 0x00.toByte()
            packet[2] = ((totalLength shr 8) and 0xFF).toByte()
            packet[3] = (totalLength and 0xFF).toByte()
            
            packet[4] = 0x00.toByte()
            packet[5] = 0x00.toByte()
            packet[6] = 0x40.toByte()
            packet[7] = 0x00.toByte()
            
            packet[8] = 64.toByte()
            packet[9] = 17.toByte() // UDP
            
            // Swap IPs
            System.arraycopy(queryPacket, 16, packet, 12, 4) // Source IP
            System.arraycopy(queryPacket, 12, packet, 16, 4) // Destination IP
            
            val ipChecksum = calculateChecksum(packet, 0, 20)
            packet[10] = ((ipChecksum shr 8) and 0xFF).toByte()
            packet[11] = (ipChecksum and 0xFF).toByte()
        } else {
            // --- IPv6 Header ---
            packet[0] = 0x60.toByte() // Version (6)
            packet[1] = 0x00.toByte()
            packet[2] = 0x00.toByte()
            packet[3] = 0x00.toByte()
            
            val payloadLen = 8 + dnsPayload.size
            packet[4] = ((payloadLen shr 8) and 0xFF).toByte()
            packet[5] = (payloadLen and 0xFF).toByte()
            
            packet[6] = 17.toByte() // Next Header: UDP
            packet[7] = 64.toByte() // Hop Limit
            
            // Swap IPv6 IPs
            System.arraycopy(queryPacket, 24, packet, 8, 16)
            System.arraycopy(queryPacket, 8, packet, 24, 16)
        }
        
        // --- UDP Header ---
        val udpOffset = ipHeaderLen
        val queryUdpOffset = if (version == 4) 20 else 40
        
        packet[udpOffset] = queryPacket[queryUdpOffset + 2]
        packet[udpOffset + 1] = queryPacket[queryUdpOffset + 3]
        packet[udpOffset + 2] = queryPacket[queryUdpOffset]
        packet[udpOffset + 3] = queryPacket[queryUdpOffset + 1]
        
        val udpLen = 8 + dnsPayload.size
        packet[udpOffset + 4] = ((udpLen shr 8) and 0xFF).toByte()
        packet[udpOffset + 5] = (udpLen and 0xFF).toByte()
        
        packet[udpOffset + 6] = 0x00.toByte()
        packet[udpOffset + 7] = 0x00.toByte()
        
        // --- DNS Payload ---
        System.arraycopy(dnsPayload, 0, packet, ipHeaderLen + 8, dnsPayload.size)
        
        return packet
    }

    private fun calculateChecksum(data: ByteArray, offset: Int, length: Int): Int {
        var sum = 0
        var i = offset
        while (i < offset + length) {
            val high = (data[i].toInt() and 0xFF) shl 8
            val low = if (i + 1 < offset + length) (data[i + 1].toInt() and 0xFF) else 0
            sum += (high or low)
            i += 2
        }
        while ((sum shr 16) > 0) {
            sum = (sum and 0xFFFF) + (sum shr 16)
        }
        return (sum.inv()) and 0xFFFF
    }
}
