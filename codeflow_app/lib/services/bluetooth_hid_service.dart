import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// HID Connection States
enum HidConnectionStatus {
  unsupported,
  unregistered,
  registered,
  connecting,
  connected,
  disconnecting,
  disconnected,
}

/// Information about a paired host Bluetooth device.
@immutable
class BluetoothHostDevice {
  final String name;
  final String address;

  const BluetoothHostDevice({required this.name, required this.address});

  factory BluetoothHostDevice.fromMap(Map<dynamic, dynamic> map) {
    return BluetoothHostDevice(
      name: map['name'] as String? ?? 'Unknown PC',
      address: map['address'] as String? ?? '',
    );
  }
}

/// Abstract contract for Bluetooth HID Keyboard emulation.
abstract class IBluetoothHidService {
  Stream<HidConnectionStatus> get connectionStatusStream;
  HidConnectionStatus get currentStatus;
  BluetoothHostDevice? get connectedHost;
  List<BluetoothHostDevice> get pairedDevices;

  Future<bool> isSupported();
  Future<bool> hasPermissions();
  Future<bool> requestPermissions();
  Future<bool> isBluetoothEnabled();
  Future<bool> enableBluetooth();
  Future<bool> requestDiscoverable({int duration = 300});
  Future<bool> registerApp({
    String? deviceName,
    String? providerName,
    String? description,
  });
  Future<bool> unregisterApp();
  Future<List<BluetoothHostDevice>> getPairedDevices();
  Future<BluetoothHostDevice?> getConnectedHost();
  Future<bool> connectHost(String address);
  Future<bool> disconnectHost();
  Future<bool> openBluetoothSettings();
  Future<void> refreshState();
  Future<bool> sendRawReport(List<int> report);
  Future<bool> sendEmergencyRelease();
  Future<bool> sendKeyPress(int hidCode, {int modifiers = 0});
  Future<bool> sendKeyChord({
    required int hidCode,
    bool ctrl = false,
    bool alt = false,
    bool shift = false,
    bool meta = false,
  });
  Future<bool> typeCharacter(String char);
  void dispose();
}

/// Standard USB HID Keyboard Scancodes
class HidScancodes {
  static const int none = 0x00;
  // Modifiers bitmasks
  static const int modLeftCtrl = 0x01;
  static const int modLeftShift = 0x02;
  static const int modLeftAlt = 0x04;
  static const int modLeftMeta = 0x08;
  static const int modRightCtrl = 0x10;
  static const int modRightShift = 0x20;
  static const int modRightAlt = 0x40;
  static const int modRightMeta = 0x80;

  // Standard Navigation & Control
  static const int enter = 0x28;
  static const int escape = 0x29;
  static const int backspace = 0x2A;
  static const int tab = 0x2B;
  static const int space = 0x2C;
  static const int arrowRight = 0x4F;
  static const int arrowLeft = 0x50;
  static const int arrowDown = 0x51;
  static const int arrowUp = 0x52;

  // Letters (a-z are 0x04 - 0x1D)
  static const int keyA = 0x04;
  static const int keyC = 0x06;
  static const int keyN = 0x11;
  static const int keyO = 0x12;
  static const int keyP = 0x13;
  static const int keyS = 0x16;
  static const int keyV = 0x19;
  static const int keyW = 0x1A;
  static const int keyZ = 0x1D;

  // Numbers (1-9 are 0x1E - 0x26, 0 is 0x27)
  static const int num1 = 0x1E;
  static const int num0 = 0x27;

  // Symbols
  static const int graveAccentTilde =
      0x35; // ` and ~ (used for VS Code terminal Ctrl+~)
  static const int minusUnderscore = 0x2D;
  static const int equalPlus = 0x2E;
  static const int bracketLeft = 0x2F;
  static const int bracketRight = 0x30;
  static const int backslash = 0x31;
  static const int semicolonColon = 0x33;
  static const int singleDoubleQuote = 0x34;
  static const int commaLess = 0x36;
  static const int periodGreater = 0x37;
  static const int slashQuestion = 0x38;

  /// Translates printable ASCII character to (hidCode, modifiers)
  static MapEntry<int, int>? charToScancode(String char) {
    if (char.isEmpty) return null;
    final codeUnit = char.codeUnitAt(0);

    // Newline / Tab / Space
    if (char == '\n' || char == '\r') return const MapEntry(enter, 0);
    if (char == '\t') return const MapEntry(tab, 0);
    if (char == ' ') return const MapEntry(space, 0);

    // Lowercase a-z (97 - 122)
    if (codeUnit >= 97 && codeUnit <= 122) {
      return MapEntry(0x04 + (codeUnit - 97), 0);
    }
    // Uppercase A-Z (65 - 90)
    if (codeUnit >= 65 && codeUnit <= 90) {
      return MapEntry(0x04 + (codeUnit - 65), modLeftShift);
    }
    // Numbers 1-9 (49 - 57)
    if (codeUnit >= 49 && codeUnit <= 57) {
      return MapEntry(0x1E + (codeUnit - 49), 0);
    }
    // Number 0 (48)
    if (codeUnit == 48) {
      return const MapEntry(num0, 0);
    }

    // Special ASCII characters
    switch (char) {
      case '!':
        return const MapEntry(num1, modLeftShift);
      case '@':
        return const MapEntry(0x1F, modLeftShift);
      case '#':
        return const MapEntry(0x20, modLeftShift);
      case '\$':
        return const MapEntry(0x21, modLeftShift);
      case '%':
        return const MapEntry(0x22, modLeftShift);
      case '^':
        return const MapEntry(0x23, modLeftShift);
      case '&':
        return const MapEntry(0x24, modLeftShift);
      case '*':
        return const MapEntry(0x25, modLeftShift);
      case '(':
        return const MapEntry(0x26, modLeftShift);
      case ')':
        return const MapEntry(num0, modLeftShift);
      case '-':
        return const MapEntry(minusUnderscore, 0);
      case '_':
        return const MapEntry(minusUnderscore, modLeftShift);
      case '=':
        return const MapEntry(equalPlus, 0);
      case '+':
        return const MapEntry(equalPlus, modLeftShift);
      case '[':
        return const MapEntry(bracketLeft, 0);
      case '{':
        return const MapEntry(bracketLeft, modLeftShift);
      case ']':
        return const MapEntry(bracketRight, 0);
      case '}':
        return const MapEntry(bracketRight, modLeftShift);
      case '\\':
        return const MapEntry(backslash, 0);
      case '|':
        return const MapEntry(backslash, modLeftShift);
      case ';':
        return const MapEntry(semicolonColon, 0);
      case ':':
        return const MapEntry(semicolonColon, modLeftShift);
      case '\'':
        return const MapEntry(singleDoubleQuote, 0);
      case '"':
        return const MapEntry(singleDoubleQuote, modLeftShift);
      case ',':
        return const MapEntry(commaLess, 0);
      case '<':
        return const MapEntry(commaLess, modLeftShift);
      case '.':
        return const MapEntry(periodGreater, 0);
      case '>':
        return const MapEntry(periodGreater, modLeftShift);
      case '/':
        return const MapEntry(slashQuestion, 0);
      case '?':
        return const MapEntry(slashQuestion, modLeftShift);
      case '`':
        return const MapEntry(graveAccentTilde, 0);
      case '~':
        return const MapEntry(graveAccentTilde, modLeftShift);
      default:
        return null;
    }
  }
}

/// Production Bluetooth HID Service communicating with Android native BluetoothHidDevice.
class BluetoothHidService extends ChangeNotifier
    implements IBluetoothHidService {
  static const MethodChannel _methodChannel = MethodChannel(
    'dev.codeflow.app/bluetooth_hid',
  );
  static const EventChannel _eventChannel = EventChannel(
    'dev.codeflow.app/bluetooth_hid_events',
  );

  final StreamController<HidConnectionStatus> _statusController =
      StreamController<HidConnectionStatus>.broadcast();
  StreamSubscription? _eventSubscription;

  HidConnectionStatus _currentStatus = HidConnectionStatus.unregistered;
  BluetoothHostDevice? _connectedHost;
  List<BluetoothHostDevice> _pairedDevices = [];

  BluetoothHidService() {
    _initEventListener();
    refreshState();
  }

  @override
  Stream<HidConnectionStatus> get connectionStatusStream =>
      _statusController.stream;

  @override
  HidConnectionStatus get currentStatus => _currentStatus;

  @override
  BluetoothHostDevice? get connectedHost => _connectedHost;

  @override
  List<BluetoothHostDevice> get pairedDevices =>
      List.unmodifiable(_pairedDevices);

  void _initEventListener() {
    // Only listen on Android where the native channel is supported
    if (!kIsWeb && Platform.isAndroid) {
      _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
        (dynamic event) {
          if (event is Map) {
            final eventType = event['event'] as String?;
            if (eventType == 'connection_state_changed') {
              final stateStr = event['state'] as String?;
              switch (stateStr) {
                case 'connected':
                  _currentStatus = HidConnectionStatus.connected;
                  if (event['device'] is Map) {
                    _connectedHost = BluetoothHostDevice.fromMap(
                      event['device'] as Map<dynamic, dynamic>,
                    );
                  }
                  break;
                case 'connecting':
                  _currentStatus = HidConnectionStatus.connecting;
                  break;
                case 'disconnecting':
                  _currentStatus = HidConnectionStatus.disconnecting;
                  break;
                case 'disconnected':
                default:
                  _currentStatus = HidConnectionStatus.disconnected;
                  _connectedHost = null;
                  break;
              }
              _statusController.add(_currentStatus);
              notifyListeners();
            } else if (eventType == 'registration_state_changed') {
              final registered = event['registered'] as bool? ?? false;
              _currentStatus = registered
                  ? HidConnectionStatus.registered
                  : HidConnectionStatus.unregistered;
              _statusController.add(_currentStatus);
              notifyListeners();
            } else if (eventType == 'paired_devices_changed') {
              final list = event['devices'] as List? ?? [];
              _pairedDevices = list
                  .whereType<Map<dynamic, dynamic>>()
                  .map((m) => BluetoothHostDevice.fromMap(m))
                  .toList();
              notifyListeners();
            }
          }
        },
        onError: (Object err) {
          debugPrint('BluetoothHidService event error: $err');
        },
      );
    } else {
      // Non-Android platforms (iOS / Desktop / Web)
      _currentStatus = HidConnectionStatus.unsupported;
      _statusController.add(_currentStatus);
      notifyListeners();
    }
  }

  @override
  Future<void> refreshState() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final paired = await getPairedDevices();
      _pairedDevices = paired;
      final connected = await getConnectedHost();
      if (connected != null) {
        _connectedHost = connected;
        _currentStatus = HidConnectionStatus.connected;
      } else if (_currentStatus == HidConnectionStatus.connected) {
        _currentStatus = HidConnectionStatus.disconnected;
        _connectedHost = null;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error refreshing HID state: $e');
    }
  }

  @override
  Future<BluetoothHostDevice?> getConnectedHost() async {
    if (kIsWeb || !Platform.isAndroid) return _connectedHost;
    try {
      final res = await _methodChannel.invokeMapMethod<dynamic, dynamic>(
        'getConnectedHost',
      );
      if (res != null) {
        _connectedHost = BluetoothHostDevice.fromMap(res);
        return _connectedHost;
      }
      return null;
    } catch (e) {
      debugPrint('Error getting connected host: $e');
      return null;
    }
  }

  @override
  Future<bool> openBluetoothSettings() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final res = await _methodChannel.invokeMethod<bool>(
        'openBluetoothSettings',
      );
      return res ?? false;
    } catch (e) {
      debugPrint('Error opening Bluetooth settings: $e');
      return false;
    }
  }

  @override
  Future<bool> isSupported() async {
    if (kIsWeb || !Platform.isAndroid) {
      return false;
    }
    try {
      final res = await _methodChannel.invokeMethod<bool>('isSupported');
      return res ?? false;
    } catch (e) {
      debugPrint('Error checking HID support: $e');
      return false;
    }
  }

  @override
  Future<bool> hasPermissions() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final res = await _methodChannel.invokeMethod<bool>('hasPermissions');
      return res ?? false;
    } catch (e) {
      debugPrint('Error checking permissions: $e');
      return false;
    }
  }

  @override
  Future<bool> requestPermissions() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final res = await _methodChannel.invokeMethod<bool>('requestPermissions');
      return res ?? false;
    } catch (e) {
      debugPrint('Error requesting permissions: $e');
      return false;
    }
  }

  @override
  Future<bool> isBluetoothEnabled() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final res = await _methodChannel.invokeMethod<bool>('isBluetoothEnabled');
      return res ?? false;
    } catch (e) {
      debugPrint('Error checking Bluetooth enabled: $e');
      return false;
    }
  }

  @override
  Future<bool> enableBluetooth() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final res = await _methodChannel.invokeMethod<bool>('enableBluetooth');
      return res ?? false;
    } catch (e) {
      debugPrint('Error enabling Bluetooth: $e');
      return false;
    }
  }

  @override
  Future<bool> requestDiscoverable({int duration = 300}) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final res = await _methodChannel.invokeMethod<bool>(
        'requestDiscoverable',
        {'duration': duration},
      );
      return res ?? false;
    } catch (e) {
      debugPrint('Error requesting discoverable: $e');
      return false;
    }
  }

  @override
  Future<bool> registerApp({
    String? deviceName,
    String? providerName,
    String? description,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final res = await _methodChannel.invokeMethod<bool>('registerApp', {
        'deviceName': deviceName ?? 'Logitech MX Keys',
        'providerName': providerName ?? 'Logitech Inc.',
        'description': description ?? 'Wireless Bluetooth Keyboard',
      });
      return res ?? false;
    } catch (e) {
      debugPrint('Error registering HID app: $e');
      rethrow;
    }
  }

  @override
  Future<bool> unregisterApp() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final res = await _methodChannel.invokeMethod<bool>('unregisterApp');
      return res ?? false;
    } catch (e) {
      debugPrint('Error unregistering HID app: $e');
      return false;
    }
  }

  @override
  Future<List<BluetoothHostDevice>> getPairedDevices() async {
    if (kIsWeb || !Platform.isAndroid) return const [];
    try {
      final res = await _methodChannel.invokeListMethod<Map<dynamic, dynamic>>(
        'getPairedDevices',
      );
      if (res == null) return const [];
      return res.map((m) => BluetoothHostDevice.fromMap(m)).toList();
    } catch (e) {
      debugPrint('Error fetching paired devices: $e');
      return const [];
    }
  }

  @override
  Future<bool> connectHost(String address) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    _currentStatus = HidConnectionStatus.connecting;
    notifyListeners();
    try {
      final res = await _methodChannel.invokeMethod<bool>('connectHost', {
        'address': address,
      });
      await Future.delayed(const Duration(milliseconds: 300));
      await refreshState();
      return res ?? false;
    } catch (e) {
      debugPrint('Error connecting host: $e');
      _currentStatus = HidConnectionStatus.disconnected;
      notifyListeners();
      return false;
    }
  }

  @override
  Future<bool> disconnectHost() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    _currentStatus = HidConnectionStatus.disconnecting;
    notifyListeners();
    try {
      final res = await _methodChannel.invokeMethod<bool>('disconnectHost');
      _connectedHost = null;
      _currentStatus = HidConnectionStatus.disconnected;
      notifyListeners();
      return res ?? false;
    } catch (e) {
      debugPrint('Error disconnecting host: $e');
      return false;
    }
  }

  @override
  Future<bool> sendRawReport(List<int> report) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final res = await _methodChannel.invokeMethod<bool>('sendReport', {
        'reportId': 0,
        'data': report,
      });
      return res ?? false;
    } catch (e) {
      debugPrint('Error sending raw HID report: $e');
      return false;
    }
  }

  @override
  Future<bool> sendEmergencyRelease() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final res = await _methodChannel.invokeMethod<bool>(
        'sendEmergencyRelease',
      );
      return res ?? false;
    } catch (e) {
      debugPrint('Error sending emergency release: $e');
      return false;
    }
  }

  @override
  Future<bool> sendKeyPress(int hidCode, {int modifiers = 0}) async {
    // 1. Key Down report: [modifiers, 0, hidCode, 0, 0, 0, 0, 0]
    final keyDownReport = [
      modifiers,
      0x00,
      hidCode,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
    ];
    final success = await sendRawReport(keyDownReport);
    if (!success) return false;

    // Small delay between keydown and keyup for host OS debouncing
    await Future.delayed(const Duration(milliseconds: 12));

    // 2. Key Up report: all zeros
    return sendRawReport(const [0, 0, 0, 0, 0, 0, 0, 0]);
  }

  @override
  Future<bool> sendKeyChord({
    required int hidCode,
    bool ctrl = false,
    bool alt = false,
    bool shift = false,
    bool meta = false,
  }) {
    int modifiers = 0;
    if (ctrl) modifiers |= HidScancodes.modLeftCtrl;
    if (alt) modifiers |= HidScancodes.modLeftAlt;
    if (shift) modifiers |= HidScancodes.modLeftShift;
    if (meta) modifiers |= HidScancodes.modLeftMeta;
    return sendKeyPress(hidCode, modifiers: modifiers);
  }

  @override
  Future<bool> typeCharacter(String char) async {
    final entry = HidScancodes.charToScancode(char);
    if (entry == null) {
      // Unsupported direct character
      return false;
    }
    return sendKeyPress(entry.key, modifiers: entry.value);
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _statusController.close();
    super.dispose();
  }
}
