import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../services/bluetooth_hid_service.dart';
import '../../services/companion_discovery_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final List<DiscoveredCompanion> _discoveredCompanions = [];
  bool _isSearching = false;
  List<BluetoothHostDevice> _pairedHosts = [];

  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _tokenController;
  late TextEditingController _postRunController;
  bool _isRegisteringHid = false;

  @override
  void initState() {
    super.initState();
    final storage = ref.read(localStorageProvider);
    _hostController = TextEditingController(text: storage.companionHost);
    _portController = TextEditingController(
      text: storage.companionPort.toString(),
    );
    _tokenController = TextEditingController(
      text: storage.companionToken ?? '',
    );
    _postRunController = TextEditingController(
      text: storage.postRunCommand,
    );
    _loadPairedBluetoothDevices();
  }

  Future<void> _loadPairedBluetoothDevices() async {
    final hid = ref.read(hidServiceProvider);
    final devices = await hid.getPairedDevices();
    if (mounted) {
      setState(() {
        _pairedHosts = devices;
      });
    }
  }

  Future<void> _registerHidWithSpoofer() async {
    setState(() => _isRegisteringHid = true);
    final hid = ref.read(hidServiceProvider);
    final storage = ref.read(localStorageProvider);
    final profile = storage.spooferProfile;

    String provider = 'Logitech Inc.';
    if (profile.contains('Apple')) {
      provider = 'Apple Inc.';
    } else if (profile.contains('Dell')) {
      provider = 'Dell Inc.';
    } else if (profile.contains('CodeFlow')) {
      provider = 'CodeFlow';
    }

    try {
      final ok = await hid.registerApp(
        deviceName: profile,
        providerName: provider,
        description: 'Wireless Bluetooth HID Keyboard',
      );

      // Make discoverable for 300 seconds so PC Bluetooth search finds it
      await hid.requestDiscoverable(duration: 300);
      await _loadPairedBluetoothDevices();

      if (mounted) {
        setState(() => _isRegisteringHid = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok
                  ? 'Registered as "$profile" and discoverable! Open PC Bluetooth Settings and pair.'
                  : 'HID registration returned false. Please check Bluetooth permissions.',
            ),
            backgroundColor: ok ? AppColors.statusSuccess : AppColors.statusWarning,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRegisteringHid = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Registration error: $e'),
            backgroundColor: AppColors.statusError,
            action: SnackBarAction(
              label: 'Permissions',
              textColor: Colors.white,
              onPressed: () => hid.requestPermissions(),
            ),
          ),
        );
      }
    }
  }

  void _startDiscovery() {
    setState(() {
      _discoveredCompanions.clear();
      _isSearching = true;
    });

    final discovery = ref.read(discoveryServiceProvider);
    discovery.discoverCompanions().listen(
      (comp) {
        if (mounted) {
          setState(() {
            if (!_discoveredCompanions.any((c) => c.host == comp.host)) {
              _discoveredCompanions.add(comp);
            }
          });
        }
      },
      onDone: () {
        if (mounted) {
          setState(() => _isSearching = false);
        }
      },
    );
  }

  Future<void> _saveCompanionSettings() async {
    final storage = ref.read(localStorageProvider);
    final port = int.tryParse(_portController.text.trim()) ?? 8090;
    await storage.setCompanionHost(_hostController.text.trim());
    await storage.setCompanionPort(port);
    await storage.setCompanionToken(
      _tokenController.text.trim().isNotEmpty
          ? _tokenController.text.trim()
          : null,
    );
    ref.read(companionStatusProvider.notifier).checkConnection();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Companion settings saved.')),
      );
    }
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _tokenController.dispose();
    _postRunController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark
        ? AppColors.darkSurface
        : AppColors.lightSurface;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    final themeMode = ref.watch(themeModeProvider);
    final hid = ref.watch(hidServiceProvider);
    final storage = ref.watch(localStorageProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            // Theme Section
            _buildSectionHeader('Appearance'),
            Container(
              decoration: BoxDecoration(
                color: surfaceColor,
                border: Border.all(color: borderColor),
                borderRadius: BorderRadius.circular(6),
              ),
              child: RadioGroup<ThemeMode>(
                groupValue: themeMode,
                onChanged: (val) {
                  if (val != null) {
                    ref.read(themeModeProvider.notifier).setMode(val);
                  }
                },
                child: Column(
                  children: [
                    RadioListTile<ThemeMode>(
                      dense: true,
                      title: const Text(
                        'System Default',
                        style: TextStyle(fontSize: 13),
                      ),
                      value: ThemeMode.system,
                    ),
                    Divider(height: 1, color: borderColor),
                    RadioListTile<ThemeMode>(
                      dense: true,
                      title: const Text(
                        'Light (White-First)',
                        style: TextStyle(fontSize: 13),
                      ),
                      value: ThemeMode.light,
                    ),
                    Divider(height: 1, color: borderColor),
                    RadioListTile<ThemeMode>(
                      dense: true,
                      title: const Text(
                        'Dark (Charcoal)',
                        style: TextStyle(fontSize: 13),
                      ),
                      value: ThemeMode.dark,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Companion Connection Section
            _buildSectionHeader('PC Companion Connection'),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: surfaceColor,
                border: Border.all(color: borderColor),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _hostController,
                    decoration: const InputDecoration(
                      labelText: 'Host IP / Hostname',
                      hintText: '192.168.1.5',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _portController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Port',
                            hintText: '8090',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: _saveCompanionSettings,
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _tokenController,
                    decoration: const InputDecoration(
                      labelText: 'Auth Token (Optional)',
                      hintText: 'Token if --token set on companion',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        icon: _isSearching
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.wifi_find, size: 16),
                        label: Text(
                          _isSearching ? 'Searching LAN...' : 'Scan LAN for PC',
                        ),
                        onPressed: _isSearching ? null : _startDiscovery,
                      ),
                    ],
                  ),
                  if (_discoveredCompanions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Discovered Companions:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ..._discoveredCompanions.map((comp) {
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.computer, size: 18),
                        title: Text(
                          '${comp.hostname} (${comp.os})',
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: Text(
                          '${comp.host}:${comp.port}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                        trailing: TextButton(
                          onPressed: () {
                            _hostController.text = comp.host;
                            _portController.text = comp.port.toString();
                            _saveCompanionSettings();
                          },
                          child: const Text('Connect'),
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Automation Execution Mode
            _buildSectionHeader('Automation Mode & Workflow Pipeline'),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: surfaceColor,
                border: Border.all(color: borderColor),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RadioGroup<String>(
                    groupValue: storage.automationMode,
                    onChanged: (val) async {
                      if (val != null) {
                        await storage.setAutomationMode(val);
                        setState(() {});
                      }
                    },
                    child: Column(
                      children: const [
                        RadioListTile<String>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('Real Human Bluetooth HID Typing (Default)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: Text('Emulates genuine physical keyboard. Automatically opens terminal (Ctrl+~), types shell injection command, types code with human jitter & pauses, and triggers save (Ctrl+S).', style: TextStyle(fontSize: 11)),
                          value: 'hidHumanTyping',
                        ),
                        Divider(height: 16),
                        RadioListTile<String>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('Direct Network Sync (Instant Companion API)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: Text('Writes files directly to disk over local companion HTTP connection. Bypasses keystroke typing.', style: TextStyle(fontSize: 11)),
                          value: 'directNetwork',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _postRunController,
                          decoration: const InputDecoration(
                            labelText: 'Post-Run Terminal Command (Optional)',
                            hintText: 'e.g. npm test, python main.py, or cargo run',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () async {
                          await storage.setPostRunCommand(_postRunController.text);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Post-run command saved.')),
                            );
                          }
                        },
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Bluetooth HID Hardware Spoofer & Host Pairing
            _buildSectionHeader('Bluetooth HID Keyboard Spoofer'),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: surfaceColor,
                border: Border.all(color: borderColor),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.bluetooth,
                        size: 20,
                        color: AppColors.accentLight,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Status: ${_statusName(hid.currentStatus)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Spoofer device identity selector
                  DropdownButtonFormField<String>(
                    initialValue: storage.spooferProfile,
                    decoration: const InputDecoration(
                      labelText: 'Hardware Keyboard Spoofer Identity',
                      helperText: 'Identity advertised to PC Bluetooth search',
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Logitech MX Keys',
                        child: Text('Logitech MX Keys Wireless (Recommended)'),
                      ),
                      DropdownMenuItem(
                        value: 'Apple Magic Keyboard',
                        child: Text('Apple Magic Keyboard'),
                      ),
                      DropdownMenuItem(
                        value: 'Dell Pro Wireless Keyboard',
                        child: Text('Dell Pro Wireless Keyboard'),
                      ),
                      DropdownMenuItem(
                        value: 'CodeFlow Hardware Keyboard',
                        child: Text('CodeFlow Hardware Keyboard'),
                      ),
                    ],
                    onChanged: (val) async {
                      if (val != null) {
                        await storage.setSpooferProfile(val);
                        setState(() {});
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          icon: _isRegisteringHid
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.bluetooth_searching, size: 16),
                          label: Text(
                            _isRegisteringHid
                                ? 'Registering...'
                                : '1-Tap Register & Discover (300s)',
                          ),
                          onPressed: _isRegisteringHid ? null : _registerHidWithSpoofer,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Steps to Pair: Tap the button above -> Open your PC Bluetooth Settings -> Find the spoofed keyboard (e.g. "Logitech MX Keys") -> Click Pair.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.lightTextMuted,
                    ),
                  ),
                  if (_pairedHosts.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text(
                      'Paired PC Hosts:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ..._pairedHosts.map((dev) {
                      final isConnected = hid.connectedHost?.address == dev.address;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.keyboard,
                          size: 18,
                          color: isConnected ? AppColors.statusSuccess : AppColors.lightTextMuted,
                        ),
                        title: Text(
                          dev.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isConnected ? FontWeight.w700 : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(
                          '${dev.address}${isConnected ? ' • CONNECTED' : ''}',
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: isConnected ? AppColors.statusSuccess : AppColors.lightTextMuted,
                          ),
                        ),
                        trailing: FilledButton.tonal(
                          onPressed: () async {
                            final ok = await hid.connectHost(dev.address);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    ok
                                        ? 'Connecting HID to ${dev.name}...'
                                        : 'Failed to initiate connection to ${dev.name}',
                                  ),
                                ),
                              );
                            }
                          },
                          child: Text(isConnected ? 'Reconnect' : 'Connect'),
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Diagnostics & Platform Compatibility
            _buildSectionHeader('Diagnostics & Platform Capabilities'),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: surfaceColor,
                border: Border.all(color: borderColor),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• Bluetooth HID Device: Supported on Android 9+ (API 28+). Note: iOS limits custom HID peripheral device registration.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '• Direct File Transfer: High-speed authenticated transfer via companion HTTP API directly into authorized PC workspace.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '• Screen Stream: Low-latency MJPEG stream with sub-second reconnection and bandwidth throttle protection.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 2.0),
      child: Text(
        title,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }

  String _statusName(HidConnectionStatus status) {
    switch (status) {
      case HidConnectionStatus.connected:
        return 'Connected to Host';
      case HidConnectionStatus.connecting:
        return 'Connecting...';
      case HidConnectionStatus.registered:
        return 'HID Registered (Ready to Pair)';
      case HidConnectionStatus.unregistered:
        return 'Unregistered';
      case HidConnectionStatus.unsupported:
        return 'Not Supported on this OS';
      case HidConnectionStatus.disconnecting:
        return 'Disconnecting...';
      case HidConnectionStatus.disconnected:
        return 'Disconnected';
    }
  }
}
