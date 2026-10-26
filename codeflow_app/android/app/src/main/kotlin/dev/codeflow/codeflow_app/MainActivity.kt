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
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
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
import android.bluetooth.BluetoothClass
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.os.ParcelUuid
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
    private var isReceiverRegistered = false

    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingConnectDevice: BluetoothDevice? = null
    private var bleAdvertiser: BluetoothLeAdvertiser? = null
    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {}
        override fun onStartFailure(errorCode: Int) {}
    }

    @SuppressLint("MissingPermission")
    private fun startBleKeyboardAdvertising(durationSeconds: Int = 300) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return
        try {
            bleAdvertiser = bluetoothAdapter?.bluetoothLeAdvertiser
            val settings = AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
                .setConnectable(true)
                .setTimeout(durationSeconds * 1000)
                .build()

            val data = AdvertiseData.Builder()
                .setIncludeDeviceName(true)
                .addServiceUuid(ParcelUuid.fromString("00001812-0000-1000-8000-00805f9b34fb"))
                .build()

            bleAdvertiser?.stopAdvertising(advertiseCallback)
            bleAdvertiser?.startAdvertising(settings, data, advertiseCallback)
        } catch (e: Exception) {
            // Non-fatal
        }
    }

    @SuppressLint("MissingPermission")
    private fun autoRegisterDefaultApp(onDone: ((Boolean) -> Unit)? = null) {
        if (hidDevice == null || isRegistered) {
            onDone?.invoke(isRegistered)
            return
        }
        try {
            val sdp = BluetoothHidDeviceAppSdpSettings(
                "Logitech MX Keys",
                "Wireless Bluetooth Keyboard",
                "Logitech Inc.",
                BluetoothHidDevice.SUBCLASS1_KEYBOARD,
                HID_KEYBOARD_DESCRIPTOR
            )
            val qos = BluetoothHidDeviceAppQosSettings(
                BluetoothHidDeviceAppQosSettings.SERVICE_BEST_EFFORT,
                800, 9, 0, 11250,
                BluetoothHidDeviceAppQosSettings.MAX
            )
            val ok = hidDevice?.registerApp(sdp, null, qos, executor, hidCallback) ?: false
            onDone?.invoke(ok)
        } catch (e: Exception) {
            onDone?.invoke(false)
        }
    }

    @SuppressLint("MissingPermission")
    private fun ensureRegisteredAndConnect(device: BluetoothDevice) {
        if (hidDevice == null) {
            bindHidProfile { ready ->
                if (ready) {
                    ensureRegisteredAndConnect(device)
                }
            }
            return
        }
        if (!isRegistered) {
            pendingConnectDevice = device
            autoRegisterDefaultApp()
        } else {
            try {
                if (device.bondState != BluetoothDevice.BOND_BONDED) {
                    pendingConnectDevice = device
                    device.createBond()
                } else {
                    hidDevice?.connect(device)
                }
            } catch (e: Exception) {
                // Non-fatal
            }
        }
    }

    private val bluetoothReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val action = intent?.action ?: return
            when (action) {
                BluetoothDevice.ACTION_BOND_STATE_CHANGED -> {
                    @Suppress("DEPRECATION")
                    val device = intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
                    val bondState = intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, BluetoothDevice.BOND_NONE)
                    if (bondState == BluetoothDevice.BOND_BONDED && device != null) {
                        ensureRegisteredAndConnect(device)
                    }
                    notifyPairedDevicesChanged()
                }
                BluetoothDevice.ACTION_ACL_CONNECTED -> {
                    @Suppress("DEPRECATION")
                    val device = intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
                    if (device != null && connectedHostDevice == null) {
                        ensureRegisteredAndConnect(device)
                    }
                    notifyPairedDevicesChanged()
                }
                BluetoothDevice.ACTION_ACL_DISCONNECTED -> {
                    @Suppress("DEPRECATION")
                    val device = intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
                    if (device != null && connectedHostDevice?.address == device.address) {
                        connectedHostDevice = null
                    }
                    notifyPairedDevicesChanged()
                }
                BluetoothAdapter.ACTION_STATE_CHANGED -> {
                    notifyPairedDevicesChanged()
                }
            }
        }
    }

    private val hidCallback = object : BluetoothHidDevice.Callback() {
        override fun onAppStatusChanged(pluggedDevice: BluetoothDevice?, registered: Boolean) {
            super.onAppStatusChanged(pluggedDevice, registered)
            isRegistered = registered
            if (registered && pendingConnectDevice != null) {
                val target = pendingConnectDevice
                pendingConnectDevice = null
                if (target != null) {
                    try {
                        hidDevice?.connect(target)
                    } catch (e: Exception) {
                        // Non-fatal
                    }
                }
            }
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
                notifyPairedDevicesChanged()
            }
        }
    }

    private val profileListener = object : BluetoothProfile.ServiceListener {
        override fun onServiceConnected(profile: Int, proxy: BluetoothProfile?) {
            if (profile == BluetoothProfile.HID_DEVICE) {
                hidDevice = proxy as? BluetoothHidDevice
                // Check if any host is already connected to the HID profile
                try {
                    val connected = hidDevice?.getConnectedDevices() ?: emptyList()
                    if (connected.isNotEmpty()) {
                        connectedHostDevice = connected.first()
                        runOnUiThread {
                            eventSink?.success(
                                mapOf(
                                    "event" to "connection_state_changed",
                                    "state" to "connected",
                                    "device" to mapOf(
                                        "name" to (connectedHostDevice?.name ?: "PC Host"),
                                        "address" to (connectedHostDevice?.address ?: "")
                                    )
                                )
                            )
                        }
                    } else if (connectedHostDevice == null) {
                        // Auto-connect to first bonded device
                        val bonded = bluetoothAdapter?.bondedDevices ?: emptySet()
                        val firstDev = bonded.firstOrNull()
                        if (firstDev != null) {
                            hidDevice?.connect(firstDev)
                        }
                    }
                } catch (e: Exception) {
                    // Ignore
                }
                notifyPairedDevicesChanged()
            }
        }

        override fun onServiceDisconnected(profile: Int) {
            if (profile == BluetoothProfile.HID_DEVICE) {
                hidDevice = null
                isRegistered = false
                connectedHostDevice = null
                notifyPairedDevicesChanged()
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val bm = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        bluetoothAdapter = bm?.adapter

        registerBluetoothReceiver()

        if (hasRequiredPermissions()) {
            bindHidProfile()
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler(this)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(this)
    }

    private fun registerBluetoothReceiver() {
        if (isReceiverRegistered) return
        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
            addAction(BluetoothDevice.ACTION_ACL_CONNECTED)
            addAction(BluetoothDevice.ACTION_ACL_DISCONNECTED)
            addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
        }
        registerReceiver(bluetoothReceiver, filter)
        isReceiverRegistered = true
    }

    private fun notifyPairedDevicesChanged() {
        runOnUiThread {
            try {
                val bonded = bluetoothAdapter?.bondedDevices ?: emptySet()
                val list = bonded.map { dev ->
                    mapOf("name" to (dev.name ?: "Unknown Host"), "address" to dev.address)
                }
                eventSink?.success(
                    mapOf(
                        "event" to "paired_devices_changed",
                        "devices" to list
                    )
                )
            } catch (e: Exception) {
                // Non-fatal
            }
        }
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
                    startBleKeyboardAdvertising(duration)
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
            "getConnectedHost" -> {
                try {
                    val connected = hidDevice?.getConnectedDevices() ?: emptyList()
                    val dev = connectedHostDevice ?: connected.firstOrNull()
                    if (dev != null) {
                        connectedHostDevice = dev
                        result.success(
                            mapOf(
                                "name" to (dev.name ?: "Unknown PC Host"),
                                "address" to dev.address
                            )
                        )
                    } else {
                        result.success(null)
                    }
                } catch (e: Exception) {
                    result.success(null)
                }
            }
            "openBluetoothSettings" -> {
                try {
                    val intent = Intent(android.provider.Settings.ACTION_BLUETOOTH_SETTINGS)
                    startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("FAILED", e.message, null)
                }
            }
            "connectHost" -> {
                val address = call.argument<String>("address")
                if (address.isNullOrEmpty()) {
                    result.success(false)
                    return
                }
                try {
                    val device = bluetoothAdapter?.getRemoteDevice(address)
                    if (device == null) {
                        result.success(false)
                        return
                    }
                    ensureRegisteredAndConnect(device)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("CONNECT_FAILED", e.message, null)
                }
            }
            "disconnectHost" -> {
                if (connectedHostDevice != null && hidDevice != null) {
                    hidDevice?.disconnect(connectedHostDevice)
                    connectedHostDevice = null
                    notifyPairedDevicesChanged()
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
                val connected = hidDevice?.getConnectedDevices() ?: emptyList()
                result.success(connectedHostDevice != null || connected.isNotEmpty())
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

        // Attempt to spoof Class of Device to Peripheral / Keyboard
        try {
            val btClassConstructor = BluetoothClass::class.java.getDeclaredConstructor(Int::class.javaPrimitiveType)
            btClassConstructor.isAccessible = true
            val keyboardClass = btClassConstructor.newInstance(0x002540)
            val setClassMethod = BluetoothAdapter::class.java.getDeclaredMethod("setBluetoothClass", BluetoothClass::class.java)
            setClassMethod.isAccessible = true
            setClassMethod.invoke(bluetoothAdapter, keyboardClass)
        } catch (e: Exception) {
            // Non-fatal if blocked
        }

        startBleKeyboardAdvertising(300)

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
        notifyPairedDevicesChanged()
    }

    override fun onCancel(arguments: Any?) {
        this.eventSink = null
    }

    override fun onDestroy() {
        super.onDestroy()
        if (isReceiverRegistered) {
            try {
                unregisterReceiver(bluetoothReceiver)
            } catch (e: Exception) {
                // Ignore
            }
            isReceiverRegistered = false
        }
        stopForegroundServiceInternal()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            hidDevice?.unregisterApp()
            bluetoothAdapter?.closeProfileProxy(BluetoothProfile.HID_DEVICE, hidDevice)
        }
        executor.shutdown()
    }
}
