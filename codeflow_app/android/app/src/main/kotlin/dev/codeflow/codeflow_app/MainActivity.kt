package dev.codeflow.codeflow_app

import android.Manifest
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
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
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
        private const val REQUEST_BT_PERMISSIONS = 1001

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
    private val mainHandler = Handler(Looper.getMainLooper())

    private var pendingPermissionResult: MethodChannel.Result? = null

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

        if (hasRequiredPermissions()) {
            bindHidProfile()
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler(this)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(this)
    }

    private fun hasRequiredPermissions(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val connectGranted = ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.BLUETOOTH_CONNECT
            ) == PackageManager.PERMISSION_GRANTED
            val advertiseGranted = ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.BLUETOOTH_ADVERTISE
            ) == PackageManager.PERMISSION_GRANTED
            return connectGranted && advertiseGranted
        } else {
            val btGranted = ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.BLUETOOTH
            ) == PackageManager.PERMISSION_GRANTED
            val btAdminGranted = ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.BLUETOOTH_ADMIN
            ) == PackageManager.PERMISSION_GRANTED
            return btGranted && btAdminGranted
        }
    }

    private fun requestRequiredPermissions(result: MethodChannel.Result? = null) {
        pendingPermissionResult = result
        val perms = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(
                Manifest.permission.BLUETOOTH_CONNECT,
                Manifest.permission.BLUETOOTH_ADVERTISE,
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.ACCESS_FINE_LOCATION
            )
        } else {
            arrayOf(
                Manifest.permission.BLUETOOTH,
                Manifest.permission.BLUETOOTH_ADMIN,
                Manifest.permission.ACCESS_FINE_LOCATION
            )
        }
        ActivityCompat.requestPermissions(this, perms, REQUEST_BT_PERMISSIONS)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_BT_PERMISSIONS) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            if (granted) {
                bindHidProfile()
            }
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }

    private fun bindHidProfile(onConnected: ((Boolean) -> Unit)? = null) {
        if (hidDevice != null) {
            onConnected?.invoke(true)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && bluetoothAdapter != null) {
            try {
                val ok = bluetoothAdapter?.getProfileProxy(
                    this,
                    object : BluetoothProfile.ServiceListener {
                        override fun onServiceConnected(profile: Int, proxy: BluetoothProfile?) {
                            if (profile == BluetoothProfile.HID_DEVICE) {
                                hidDevice = proxy as? BluetoothHidDevice
                                profileListener.onServiceConnected(profile, proxy)
                                mainHandler.post { onConnected?.invoke(true) }
                            }
                        }

                        override fun onServiceDisconnected(profile: Int) {
                            profileListener.onServiceDisconnected(profile)
                        }
                    },
                    BluetoothProfile.HID_DEVICE
                ) ?: false

                if (!ok) {
                    onConnected?.invoke(false)
                }
            } catch (e: Exception) {
                onConnected?.invoke(false)
            }
        } else {
            onConnected?.invoke(false)
        }
    }

    @SuppressLint("MissingPermission")
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> {
                val supported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && bluetoothAdapter != null
                result.success(supported)
            }
            "hasPermissions" -> {
                result.success(hasRequiredPermissions())
            }
            "requestPermissions" -> {
                if (hasRequiredPermissions()) {
                    result.success(true)
                } else {
                    requestRequiredPermissions(result)
                }
            }
            "isBluetoothEnabled" -> {
                result.success(bluetoothAdapter?.isEnabled == true)
            }
            "enableBluetooth" -> {
                try {
                    val enableBtIntent = Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)
                    startActivity(enableBtIntent)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("ENABLE_BT_FAILED", e.message, null)
                }
            }
            "requestDiscoverable" -> {
                try {
                    val duration = call.argument<Int>("duration") ?: 300
                    val discoverableIntent = Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE).apply {
                        putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, duration)
                    }
                    startActivity(discoverableIntent)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("DISCOVERABLE_FAILED", e.message, null)
                }
            }
            "registerApp" -> {
                if (!hasRequiredPermissions()) {
                    requestRequiredPermissions(object : MethodChannel.Result {
                        override fun success(res: Any?) {
                            if (res == true) {
                                proceedRegister(call, result)
                            } else {
                                result.error("PERMISSION_DENIED", "Bluetooth connect & advertise permissions are required.", null)
                            }
                        }
                        override fun error(code: String, msg: String?, details: Any?) {
                            result.error(code, msg, details)
                        }
                        override fun notImplemented() {
                            result.notImplemented()
                        }
                    })
                    return
                }

                proceedRegister(call, result)
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

    @SuppressLint("MissingPermission")
    private fun proceedRegister(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            result.error("UNSUPPORTED", "Bluetooth HID Device requires Android 9 (API 28) or higher.", null)
            return
        }

        if (bluetoothAdapter?.isEnabled == false) {
            try {
                val enableBtIntent = Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)
                startActivity(enableBtIntent)
            } catch (e: Exception) {
                // Ignore
            }
            result.error("BLUETOOTH_DISABLED", "Please enable Bluetooth in your device settings.", null)
            return
        }

        val deviceName = call.argument<String>("deviceName") ?: "Logitech MX Keys"
        val providerName = call.argument<String>("providerName") ?: "Logitech Inc."
        val description = call.argument<String>("description") ?: "Wireless Bluetooth Keyboard"

        // Attempt to rename adapter to spoof hardware brand
        try {
            bluetoothAdapter?.name = deviceName
        } catch (e: Exception) {
            // Non-fatal if device prevents rename
        }

        fun executeRegistration() {
            if (hidDevice == null) {
                result.error("PROXY_UNAVAILABLE", "Android Bluetooth HID service proxy is not connected.", null)
                return
            }
            try {
                val sdp = BluetoothHidDeviceAppSdpSettings(
                    deviceName,
                    description,
                    providerName,
                    BluetoothHidDevice.SUBCLASS1_KEYBOARD,
                    HID_KEYBOARD_DESCRIPTOR
                )
                val qos = BluetoothHidDeviceAppQosSettings(
                    BluetoothHidDeviceAppQosSettings.SERVICE_BEST_EFFORT,
                    800, 9, 0, 11250,
                    BluetoothHidDeviceAppQosSettings.MAX
                )
                val registered = hidDevice?.registerApp(sdp, null, qos, executor, hidCallback) ?: false
                result.success(registered)
            } catch (e: Exception) {
                result.error("REGISTRATION_FAILED", e.message, null)
            }
        }

        if (hidDevice != null) {
            executeRegistration()
        } else {
            bindHidProfile { ready ->
                if (ready && hidDevice != null) {
                    executeRegistration()
                } else {
                    result.error("PROXY_TIMEOUT", "Failed to connect to Bluetooth HID service. Please verify Bluetooth is turned ON.", null)
                }
            }
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
