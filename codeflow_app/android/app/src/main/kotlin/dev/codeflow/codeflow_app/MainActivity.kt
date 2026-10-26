package dev.codeflow.codeflow_app

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHidDevice
import android.bluetooth.BluetoothHidDeviceAppQosSettings
import android.bluetooth.BluetoothHidDeviceAppSdpSettings
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity(), MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        private const val METHOD_CHANNEL = "dev.codeflow.app/bluetooth_hid"
        private const val EVENT_CHANNEL = "dev.codeflow.app/bluetooth_hid_events"

        // Standard USB HID Keyboard Descriptor
        private val HID_KEYBOARD_DESCRIPTOR = byteArrayOf(
            0x05.toByte(), 0x01.toByte(), // Usage Page (Generic Desktop)
            0x09.toByte(), 0x06.toByte(), // Usage (Keyboard)
            0xA1.toByte(), 0x01.toByte(), // Collection (Application)
            0x05.toByte(), 0x07.toByte(), //   Usage Page (Key Codes)
            0x19.toByte(), 0xE0.toByte(), //   Usage Minimum (224)
            0x29.toByte(), 0xE7.toByte(), //   Usage Maximum (231)
            0x15.toByte(), 0x00.toByte(), //   Logical Minimum (0)
            0x25.toByte(), 0x01.toByte(), //   Logical Maximum (1)
            0x75.toByte(), 0x01.toByte(), //   Report Size (1)
            0x95.toByte(), 0x08.toByte(), //   Report Count (8)
            0x81.toByte(), 0x02.toByte(), //   Input (Data, Variable, Absolute) - Modifiers
            0x95.toByte(), 0x01.toByte(), //   Report Count (1)
            0x75.toByte(), 0x08.toByte(), //   Report Size (8)
            0x81.toByte(), 0x01.toByte(), //   Input (Constant) - Reserved byte
            0x95.toByte(), 0x05.toByte(), //   Report Count (5)
            0x75.toByte(), 0x01.toByte(), //   Report Size (1)
            0x05.toByte(), 0x08.toByte(), //   Usage Page (LEDs)
            0x19.toByte(), 0x01.toByte(), //   Usage Minimum (1)
            0x29.toByte(), 0x05.toByte(), //   Usage Maximum (5)
            0x91.toByte(), 0x02.toByte(), //   Output (Data, Variable, Absolute) - LEDs
            0x95.toByte(), 0x01.toByte(), //   Report Count (1)
            0x75.toByte(), 0x03.toByte(), //   Report Size (3)
            0x91.toByte(), 0x01.toByte(), //   Output (Constant) - LED padding
            0x95.toByte(), 0x06.toByte(), //   Report Count (6)
            0x75.toByte(), 0x08.toByte(), //   Report Size (8)
            0x15.toByte(), 0x00.toByte(), //   Logical Minimum (0)
            0x25.toByte(), 0x65.toByte(), //   Logical Maximum (101)
            0x05.toByte(), 0x07.toByte(), //   Usage Page (Key Codes)
            0x19.toByte(), 0x00.toByte(), //   Usage Minimum (0)
            0x29.toByte(), 0x65.toByte(), //   Usage Maximum (101)
            0x81.toByte(), 0x00.toByte(), //   Input (Data, Array) - Key arrays
            0xC0.toByte()                 // End Collection
        )
    }

    private var bluetoothAdapter: BluetoothAdapter? = null
    private var hidDevice: BluetoothHidDevice? = null
    private var isRegistered = false
    private var connectedHostDevice: BluetoothDevice? = null
    private var eventSink: EventChannel.EventSink? = null
    private val executor = Executors.newSingleThreadExecutor()

    private val hidCallback = object : BluetoothHidDevice.Callback() {
        override fun onAppStatusChanged(pluggedDevice: BluetoothDevice?, registered: Boolean) {
            super.onAppStatusChanged(pluggedDevice, registered)
            isRegistered = registered
            runOnUiThread {
                eventSink?.success(
                    mapOf(
                        "event" to "registration_state_changed",
                        "registered" to registered
                    )
                )
            }
        }

        override fun onConnectionStateChanged(device: BluetoothDevice?, state: Int) {
            super.onConnectionStateChanged(device, state)
            val stateName = when (state) {
                BluetoothProfile.STATE_CONNECTED -> {
                    connectedHostDevice = device
                    startForegroundServiceInternal()
                    "connected"
                }
                BluetoothProfile.STATE_CONNECTING -> "connecting"
                BluetoothProfile.STATE_DISCONNECTING -> "disconnecting"
                BluetoothProfile.STATE_DISCONNECTED -> {
                    if (connectedHostDevice?.address == device?.address) {
                        connectedHostDevice = null
                    }
                    stopForegroundServiceInternal()
                    "disconnected"
                }
                else -> "unknown"
            }

            runOnUiThread {
                val payload = mutableMapOf<String, Any>(
                    "event" to "connection_state_changed",
                    "state" to stateName
                )
                if (device != null) {
                    payload["device"] = mapOf(
                        "name" to (device.name ?: "Unknown Host"),
                        "address" to device.address
                    )
                }
                eventSink?.success(payload)
            }
        }
    }

    private val profileListener = object : BluetoothProfile.ServiceListener {
        override fun onServiceConnected(profile: Int, proxy: BluetoothProfile?) {
            if (profile == BluetoothProfile.HID_DEVICE) {
                hidDevice = proxy as? BluetoothHidDevice
            }
        }

        override fun onServiceDisconnected(profile: Int) {
            if (profile == BluetoothProfile.HID_DEVICE) {
                hidDevice = null
                isRegistered = false
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val bm = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        bluetoothAdapter = bm?.adapter

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && bluetoothAdapter != null) {
            bluetoothAdapter?.getProfileProxy(this, profileListener, BluetoothProfile.HID_DEVICE)
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler(this)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(this)
    }

    @SuppressLint("MissingPermission")
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> {
                val supported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && bluetoothAdapter != null
                result.success(supported)
            }
            "registerApp" -> {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P || hidDevice == null) {
                    result.success(false)
                    return
                }
                try {
                    val sdp = BluetoothHidDeviceAppSdpSettings(
                        "CodeFlow Keyboard",
                        "CodeFlow Automation Keyboard",
                        "CodeFlow",
                        BluetoothHidDevice.SUBCLASS1_KEYBOARD,
                        HID_KEYBOARD_DESCRIPTOR
                    )
                    val qos = BluetoothHidDeviceAppQosSettings(
                        BluetoothHidDeviceAppQosSettings.SERVICE_BEST_EFFORT,
                        800, 9, 0, 11250,
                        BluetoothHidDeviceAppQosSettings.MAX
                    )
                    val success = hidDevice?.registerApp(sdp, null, qos, executor, hidCallback) ?: false
                    result.success(success)
                } catch (e: Exception) {
                    result.error("REGISTRATION_FAILED", e.message, null)
                }
            }
            "unregisterApp" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    hidDevice?.unregisterApp()
                    isRegistered = false
                }
                result.success(true)
            }
            "getPairedDevices" -> {
                try {
                    val bonded = bluetoothAdapter?.bondedDevices ?: emptySet()
                    val list = bonded.map { dev ->
                        mapOf("name" to (dev.name ?: "Unknown Host"), "address" to dev.address)
                    }
                    result.success(list)
                } catch (e: Exception) {
                    result.success(emptyList<Map<String, String>>())
                }
            }
            "connectHost" -> {
                val address = call.argument<String>("address")
                if (address.isNullOrEmpty() || hidDevice == null) {
                    result.success(false)
                    return
                }
                try {
                    val device = bluetoothAdapter?.getRemoteDevice(address)
                    if (device == null) {
                        result.success(false)
                        return
                    }
                    val ok = hidDevice?.connect(device) ?: false
                    result.success(ok)
                } catch (e: Exception) {
                    result.error("CONNECT_FAILED", e.message, null)
                }
            }
            "disconnectHost" -> {
                if (connectedHostDevice != null && hidDevice != null) {
                    hidDevice?.disconnect(connectedHostDevice)
                    result.success(true)
                } else {
                    result.success(false)
                }
            }
            "sendReport" -> {
                val reportId = call.argument<Int>("reportId") ?: 0
                val data = call.argument<List<Int>>("data")
                if (data == null || connectedHostDevice == null || hidDevice == null) {
                    result.success(false)
                    return
                }
                val byteData = ByteArray(data.size) { i -> data[i].toByte() }
                val ok = hidDevice?.sendReport(connectedHostDevice, reportId, byteData) ?: false
                result.success(ok)
            }
            "sendEmergencyRelease" -> {
                if (connectedHostDevice != null && hidDevice != null) {
                    val emptyReport = ByteArray(8) { 0 }
                    val ok = hidDevice?.sendReport(connectedHostDevice, 0, emptyReport) ?: false
                    result.success(ok)
                } else {
                    result.success(false)
                }
            }
            "isHostConnected" -> {
                result.success(connectedHostDevice != null)
            }
            "startForegroundService" -> {
                startForegroundServiceInternal()
                result.success(true)
            }
            "stopForegroundService" -> {
                stopForegroundServiceInternal()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun startForegroundServiceInternal() {
        val intent = Intent(this, CodeFlowHidService::class.java)
        ContextCompat.startForegroundService(this, intent)
    }

    private fun stopForegroundServiceInternal() {
        val intent = Intent(this, CodeFlowHidService::class.java).apply {
            action = CodeFlowHidService.ACTION_STOP
        }
        startService(intent)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        this.eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        this.eventSink = null
    }

    override fun onDestroy() {
        super.onDestroy()
        stopForegroundServiceInternal()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            hidDevice?.unregisterApp()
            bluetoothAdapter?.closeProfileProxy(BluetoothProfile.HID_DEVICE, hidDevice)
        }
        executor.shutdown()
    }
}
