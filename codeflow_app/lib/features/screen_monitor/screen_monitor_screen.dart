import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import 'screen_stream_viewport.dart';

class ScreenMonitorScreen extends ConsumerWidget {
  const ScreenMonitorScreen({super.key});

  void _showConnectionDialog(BuildContext context, WidgetRef ref) {
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    final storage = ref.watch(localStorageProvider);
    final apiService = ref.watch(companionApiProvider);
    final companionState = ref.watch(companionStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('PC Screen Monitor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune, size: 20),
            tooltip: 'Connection Settings',
            onPressed: () => _showConnectionDialog(context, ref),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              // Host Info Bar
              if (companionState.isConnected && companionState.info != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
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
                    ],
                  ),
                ),

              // MJPEG Stream Viewport
              Expanded(
                child: ScreenStreamViewport(
                  host: storage.companionHost,
                  port: storage.companionPort,
                  token: storage.companionToken,
                  apiService: apiService,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
