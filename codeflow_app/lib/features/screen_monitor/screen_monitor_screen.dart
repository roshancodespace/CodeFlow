import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../models/workflow_checkpoint.dart';
import '../../services/bluetooth_hid_service.dart';
import 'screen_stream_viewport.dart';

class ScreenMonitorScreen extends ConsumerStatefulWidget {
  const ScreenMonitorScreen({super.key});

  @override
  ConsumerState<ScreenMonitorScreen> createState() => _ScreenMonitorScreenState();
}

class _ScreenMonitorScreenState extends ConsumerState<ScreenMonitorScreen> {
  final TextEditingController _commandController = TextEditingController();
  bool _isTypingCommand = false;
  bool _controlsExpanded = true;

  @override
  void dispose() {
    _commandController.dispose();
    super.dispose();
  }

  void _showConnectionDialog(BuildContext context) {
    final storage = ref.read(localStorageProvider);
    final hostController = TextEditingController(text: storage.companionHost);
    final portController = TextEditingController(text: storage.companionPort.toString());
    final tokenController = TextEditingController(text: storage.companionToken ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Companion Stream Settings', style: TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: hostController,
              decoration: const InputDecoration(
                labelText: 'Host IP / Hostname',
                hintText: '192.168.1.5 or 127.0.0.1',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: portController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Port',
                hintText: '8090',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tokenController,
              decoration: const InputDecoration(
                labelText: 'Auth Token (Optional)',
                hintText: 'Token if configured on PC',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final port = int.tryParse(portController.text.trim()) ?? 8090;
              await storage.setCompanionHost(hostController.text.trim());
              await storage.setCompanionPort(port);
              await storage.setCompanionToken(
                tokenController.text.trim().isNotEmpty
                    ? tokenController.text.trim()
                    : null,
              );
              ref.read(companionStatusProvider.notifier).checkConnection();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save & Reconnect'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendQuickCommand() async {
    final text = _commandController.text;
    if (text.isEmpty) return;

    setState(() => _isTypingCommand = true);
    final orchestrator = ref.read(orchestratorProvider);
    try {
      await orchestrator.typeQuickCommand(text, pressEnter: true);
      _commandController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error typing command: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isTypingCommand = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    final storage = ref.watch(localStorageProvider);
    final apiService = ref.watch(companionApiProvider);
    final companionState = ref.watch(companionStatusProvider);
    final hidService = ref.watch(hidServiceProvider);
    final orchestrator = ref.watch(orchestratorProvider);
    final orchState = orchestrator.state;
    final selectedProject = ref.watch(selectedProjectProvider);

    final isHostMac = (companionState.info?.os ?? '').toLowerCase().contains('darwin') ||
        (companionState.info?.os ?? '').toLowerCase().contains('mac');

    return Scaffold(
      appBar: AppBar(
        title: const Text('PC Screen & Remote HID'),
        actions: [
          IconButton(
            icon: Icon(
              _controlsExpanded ? Icons.keyboard_hide : Icons.keyboard,
              size: 20,
            ),
            tooltip: 'Toggle Remote Control Bar',
            onPressed: () => setState(() => _controlsExpanded = !_controlsExpanded),
          ),
          IconButton(
            icon: const Icon(Icons.tune, size: 20),
            tooltip: 'Connection Settings',
            onPressed: () => _showConnectionDialog(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Host Info & Active Window Bar
            if (companionState.isConnected && companionState.info != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: surfaceColor,
                  border: Border.all(color: borderColor),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.laptop, size: 16, color: AppColors.accentLight),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${companionState.info!.hostname} (${companionState.info!.os})'
                        '${companionState.info!.activeWindow != null ? " • ${companionState.info!.activeWindow}" : ""}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    InkWell(
                      onTap: () async {
                        if (hidService.connectedHost != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'HID Keyboard active with ${hidService.connectedHost!.name} (${hidService.connectedHost!.address})',
                              ),
                            ),
                          );
                        } else if (hidService.pairedDevices.isNotEmpty) {
                          final firstHost = hidService.pairedDevices.first;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Connecting HID to ${firstHost.name}...'),
                            ),
                          );
                          await hidService.connectHost(firstHost.address);
                        } else {
                          Navigator.pushNamed(context, '/settings');
                        }
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: hidService.connectedHost != null
                              ? AppColors.statusSuccess.withAlpha(25)
                              : hidService.pairedDevices.isNotEmpty
                                  ? AppColors.statusWarning.withAlpha(35)
                                  : AppColors.lightBorder.withAlpha(80),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: hidService.connectedHost != null
                                ? AppColors.statusSuccess.withAlpha(80)
                                : hidService.pairedDevices.isNotEmpty
                                    ? AppColors.statusWarning.withAlpha(120)
                                    : AppColors.lightBorder,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.keyboard,
                              size: 13,
                              color: hidService.connectedHost != null
                                  ? AppColors.statusSuccess
                                  : hidService.pairedDevices.isNotEmpty
                                      ? AppColors.statusWarning
                                      : AppColors.lightTextMuted,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              hidService.connectedHost != null
                                  ? 'Keyboard: ${hidService.connectedHost!.name}'
                                  : hidService.currentStatus == HidConnectionStatus.connecting
                                      ? 'Connecting HID...'
                                      : hidService.pairedDevices.isNotEmpty
                                          ? 'Paired: ${hidService.pairedDevices.first.name} (Tap)'
                                          : 'No Host Paired (Tap)',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: hidService.connectedHost != null
                                    ? AppColors.statusSuccess
                                    : hidService.pairedDevices.isNotEmpty
                                        ? AppColors.statusWarning
                                        : AppColors.lightTextMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Live MJPEG Screen Stream Viewport
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: ScreenStreamViewport(
                  host: storage.companionHost,
                  port: storage.companionPort,
                  token: storage.companionToken,
                  apiService: apiService,
                ),
              ),
            ),

            // Active Workflow Progress Banner
            if (orchState.status == WorkflowExecutionStatus.inProgress)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.accentLight.withAlpha(20),
                  border: Border.all(color: AppColors.accentLight),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        orchState.currentOperation,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.pause, size: 18),
                      tooltip: 'Pause Automation',
                      onPressed: () => orchestrator.pause(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.cancel, size: 18, color: AppColors.statusError),
                      tooltip: 'Cancel',
                      onPressed: () => orchestrator.cancel(),
                    ),
                  ],
                ),
              ),

            // Interactive Remote Keyboard Controls Bar
            if (_controlsExpanded)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: surfaceColor,
                  border: Border(top: BorderSide(color: borderColor)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Quick Key Chords
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ActionChip(
                            avatar: const Icon(Icons.terminal, size: 14),
                            label: Text(isHostMac ? 'Cmd + `' : 'Ctrl + `'),
                            tooltip: 'Toggle VS Code Terminal',
                            onPressed: () => orchestrator.sendShortcut(
                              hidCode: HidScancodes.graveAccentTilde,
                              ctrl: !isHostMac,
                              meta: isHostMac,
                            ),
                          ),
                          const SizedBox(width: 6),
                          ActionChip(
                            avatar: const Icon(Icons.folder_open, size: 14),
                            label: Text(isHostMac ? 'Cmd + P' : 'Ctrl + P'),
                            tooltip: 'Quick Open File in VS Code',
                            onPressed: () => orchestrator.sendShortcut(
                              hidCode: 0x13, // Key P
                              ctrl: !isHostMac,
                              meta: isHostMac,
                            ),
                          ),
                          const SizedBox(width: 6),
                          ActionChip(
                            avatar: const Icon(Icons.save, size: 14),
                            label: Text(isHostMac ? 'Cmd + S' : 'Ctrl + S'),
                            tooltip: 'Save Active Editor',
                            onPressed: () => orchestrator.sendShortcut(
                              hidCode: HidScancodes.keyS,
                              ctrl: !isHostMac,
                              meta: isHostMac,
                            ),
                          ),
                          const SizedBox(width: 6),
                          ActionChip(
                            avatar: const Icon(Icons.keyboard_return, size: 14),
                            label: const Text('Enter'),
                            onPressed: () => orchestrator.sendShortcut(
                              hidCode: HidScancodes.enter,
                            ),
                          ),
                          const SizedBox(width: 6),
                          ActionChip(
                            avatar: const Icon(Icons.close, size: 14),
                            label: const Text('Esc'),
                            onPressed: () => orchestrator.sendShortcut(
                              hidCode: HidScancodes.escape,
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (selectedProject != null)
                            ActionChip(
                              avatar: const Icon(Icons.play_arrow, size: 14, color: AppColors.accentLight),
                              label: Text('Type: ${selectedProject.name}'),
                              onPressed: () => orchestrator.runWorkflow(project: selectedProject),
                            ),
                          const SizedBox(width: 6),
                          ActionChip(
                            avatar: const Icon(Icons.warning, size: 14, color: AppColors.statusError),
                            label: const Text('PANIC', style: TextStyle(color: AppColors.statusError)),
                            onPressed: () => orchestrator.emergencyPanicRelease(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Quick Command Keystroke Input Field
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _commandController,
                            decoration: const InputDecoration(
                              hintText: 'Type command or text to inject on PC...',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                            onSubmitted: (_) => _sendQuickCommand(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _isTypingCommand ? null : _sendQuickCommand,
                          child: _isTypingCommand
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('Type to PC'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
