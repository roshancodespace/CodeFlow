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

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
  final List<DiscoveredCompanion> _discoveredCompanions = [];
  bool _isSearching = false;

  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _tokenController;
  late TextEditingController _postRunController;
  bool _isRegisteringHid = false;
  String? _connectingAddress;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final storage = ref.read(localStorageProvider);
    _hostController = TextEditingController(text: storage.companionHost);
    _portController = TextEditingController(
      text: storage.companionPort.toString(),
    );
    _tokenController = TextEditingController(
      text: storage.companionToken ?? '',
    );
    _postRunController = TextEditingController(text: storage.postRunCommand);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(hidServiceProvider).refreshState();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(hidServiceProvider).refreshState();
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
      await hid.refreshState();

      if (mounted) {
        setState(() => _isRegisteringHid = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok
                  ? 'Registered as "$profile" and discoverable! Open PC Bluetooth Settings and pair.'
                  : 'HID registration returned false. Please check Bluetooth permissions.',
            ),
            backgroundColor: ok
                ? AppColors.statusSuccess
                : AppColors.statusWarning,
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
    WidgetsBinding.instance.removeObserver(this);
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
                          title: Text(
                            'VS Code Real Developer (In-Editor Shortcuts & Typing) [Default]',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            'Uses VS Code shortcuts: Ctrl+P Quick Open to select files, focuses editor tab, clears buffer (Ctrl+A -> Backspace), types code with human typos, backspaces & cadence, and saves (Ctrl+S).',
                            style: TextStyle(fontSize: 11),
                          ),
                          value: 'vscodeEditor',
                        ),
                        Divider(height: 16),
                        RadioListTile<String>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Terminal Shell Script Injection (CLI cat/PowerShell)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            'Opens terminal (Ctrl+~) and injects file content using cat heredoc or PowerShell Set-Content.',
                            style: TextStyle(fontSize: 11),
                          ),
                          value: 'hidTerminalShell',
                        ),
                        Divider(height: 16),
                        RadioListTile<String>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Direct Network Sync (Instant Companion API)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            'Writes files directly to disk over local companion HTTP connection. Bypasses keystroke typing.',
                            style: TextStyle(fontSize: 11),
                          ),
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
                            hintText:
                                'e.g. npm test, python main.py, or cargo run',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () async {
                          await storage.setPostRunCommand(
                            _postRunController.text,
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Post-run command saved.'),
                              ),
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

            // Humanized Typing & Mistake Engine Preferences
            _buildSectionHeader('Humanized Typing & Mistakes Engine'),
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
                  // Human Typing Speed (CPS / WPM)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Human Typing Speed',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${storage.typingSpeedCps} CPS (~${(storage.typingSpeedCps * 12).round()} WPM)',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: storage.typingSpeedCps.toDouble().clamp(2.0, 30.0),
                    min: 2,
                    max: 30,
                    divisions: 28,
                    onChanged: (val) {
                      storage.setTypingSpeedCps(val.round());
                      setState(() {});
                    },
                  ),

                  // Human Mistakes & Auto-Corrections Switch
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Human Mistakes & Auto-Corrections',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      'Randomized typos on adjacent QWERTY keys with realistic human reaction delay and backspace fixes',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: storage.humanMistakesEnabled,
                    onChanged: (val) {
                      storage.setHumanMistakesEnabled(val);
                      setState(() {});
                    },
                  ),

                  if (storage.humanMistakesEnabled) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Typo Mistake Frequency',
                          style: TextStyle(fontSize: 11),
                        ),
                        Text(
                          '${storage.mistakeProbabilityPercent}% of keys',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: storage.mistakeProbabilityPercent.toDouble().clamp(
                        1.0,
                        10.0,
                      ),
                      min: 1,
                      max: 10,
                      divisions: 9,
                      onChanged: (val) {
                        storage.setMistakeProbabilityPercent(val.round());
                        setState(() {});
                      },
                    ),
                  ],

                  // Syntax & Thought Pauses Switch
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Developer Syntax & Thought Pauses',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      'Natural human hesitation at newlines, semicolons, brackets, and code intervals',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: storage.thinkingPausesEnabled,
                    onChanged: (val) {
                      storage.setThinkingPausesEnabled(val);
                      setState(() {});
                    },
                  ),

                  // Focus Countdown
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Focus Window Countdown Delay',
                        style: TextStyle(fontSize: 12),
                      ),
                      Text(
                        '${storage.focusDelaySeconds}s',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: storage.focusDelaySeconds.toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    onChanged: (val) {
                      storage.setFocusDelaySeconds(val.round());
                      setState(() {});
                    },
                  ),

                  // Newline Pause Slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Newline Formatter Catch-up Pause',
                        style: TextStyle(fontSize: 12),
                      ),
                      Text(
                        '${storage.newlinePauseMs}ms',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: storage.newlinePauseMs.toDouble().clamp(50.0, 800.0),
                    min: 50,
                    max: 800,
                    divisions: 15,
                    onChanged: (val) {
                      storage.setNewlinePauseMs(val.round());
                      setState(() {});
                    },
                  ),

                  // Gaussian Jitter Switch
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Box-Muller Gaussian Jitter',
                      style: TextStyle(fontSize: 12),
                    ),
                    subtitle: const Text(
                      'Mathematical micro-variance to mimic realistic human neuromuscular latency',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: storage.humanJitterEnabled,
                    onChanged: (val) {
                      storage.setHumanJitterEnabled(val);
                      setState(() {});
                    },
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
                          onPressed: _isRegisteringHid
                              ? null
                              : _registerHidWithSpoofer,
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
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Paired PC Hosts:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.refresh, size: 16),
                            tooltip: 'Refresh paired devices',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () async {
                              await hid.refreshState();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Refreshed paired devices (${hid.pairedDevices.length} found)',
                                    ),
                                    duration: const Duration(seconds: 1),
                                  ),
                                );
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            icon: const Icon(
                              Icons.settings_bluetooth,
                              size: 14,
                            ),
                            label: const Text(
                              'Bluetooth Settings',
                              style: TextStyle(fontSize: 11),
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => hid.openBluetoothSettings(),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (hid.pairedDevices.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkBackground
                            : AppColors.lightBackground,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(
                                Icons.bluetooth_searching,
                                size: 16,
                                color: AppColors.accentLight,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'No Paired PC Hosts Found Yet',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '1. Tap "1-Tap Register & Discover" above.\n2. On your PC, open Bluetooth Settings.\n3. Add Bluetooth device and select the advertised keyboard name.\n4. Once paired, it will appear here automatically!',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.lightTextMuted,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ...hid.pairedDevices.map((dev) {
                      final isConnected =
                          hid.connectedHost?.address == dev.address;
                      final isThisConnecting =
                          _connectingAddress == dev.address &&
                          hid.currentStatus == HidConnectionStatus.connecting;

                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.keyboard,
                          size: 20,
                          color: isConnected
                              ? AppColors.statusSuccess
                              : isThisConnecting
                              ? AppColors.statusWarning
                              : AppColors.lightTextMuted,
                        ),
                        title: Text(
                          dev.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isConnected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          isConnected
                              ? '${dev.address} • KEYBOARD ACTIVE'
                              : isThisConnecting
                              ? '${dev.address} • CONNECTING...'
                              : '${dev.address} • PAIRED',
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            fontWeight: isConnected
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: isConnected
                                ? AppColors.statusSuccess
                                : isThisConnecting
                                ? AppColors.statusWarning
                                : AppColors.lightTextMuted,
                          ),
                        ),
                        trailing: isConnected
                            ? OutlinedButton(
                                onPressed: () async {
                                  await hid.disconnectHost();
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Disconnected from ${dev.name}',
                                        ),
                                      ),
                                    );
                                  }
                                },
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text(
                                  'Disconnect',
                                  style: TextStyle(fontSize: 12),
                                ),
                              )
                            : FilledButton.tonal(
                                onPressed: isThisConnecting
                                    ? null
                                    : () async {
                                        setState(
                                          () =>
                                              _connectingAddress = dev.address,
                                        );
                                        final ok = await hid.connectHost(
                                          dev.address,
                                        );
                                        if (context.mounted) {
                                          setState(
                                            () => _connectingAddress = null,
                                          );
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                ok
                                                    ? 'Connecting HID keyboard to ${dev.name}...'
                                                    : 'Failed to initiate connection to ${dev.name}',
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: isThisConnecting
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text(
                                        'Connect Keyboard',
                                        style: TextStyle(fontSize: 12),
                                      ),
                              ),
                      );
                    }),
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
