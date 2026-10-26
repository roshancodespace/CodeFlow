import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../models/project.dart';

class HomeScreen extends ConsumerWidget {
  final void Function(int tabIndex) onNavigateTab;
  final void Function(Project project) onOpenProject;

  const HomeScreen({
    super.key,
    required this.onNavigateTab,
    required this.onOpenProject,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark
        ? AppColors.darkSurface
        : AppColors.lightSurface;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    final companionState = ref.watch(companionStatusProvider);
    final projects = ref.watch(projectsProvider);
    final storage = ref.watch(localStorageProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('CodeFlow'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 20),
            tooltip: 'Settings',
            onPressed: () => onNavigateTab(4), // Settings tab
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            // Companion Status Card
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
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: companionState.isConnected
                              ? AppColors.statusSuccess
                              : AppColors.statusWarning,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        companionState.isConnected
                            ? 'PC Companion Connected'
                            : 'Companion Offline',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          ref
                              .read(companionStatusProvider.notifier)
                              .checkConnection();
                        },
                        child: const Text(
                          'Refresh',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (companionState.isConnected &&
                      companionState.info != null) ...[
                    Text(
                      '${companionState.info!.hostname} (${companionState.info!.os}) • ${storage.companionHost}:${storage.companionPort}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.lightTextSecondary,
                        fontFamily: 'monospace',
                      ),
                    ),
                    if (companionState.info!.activeWindow != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Active: ${companionState.info!.activeWindow}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.lightTextMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (companionState.pingMs != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Round-trip latency: ${companionState.pingMs}ms',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.lightTextMuted,
                        ),
                      ),
                    ],
                  ] else ...[
                    Text(
                      'Target: ${storage.companionHost}:${storage.companionPort}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.lightTextSecondary,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Ensure codeflow_streamer.py is running on your PC.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.lightTextMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Quick Navigation Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.folder_outlined, size: 16),
                    label: const Text('Projects'),
                    onPressed: () => onNavigateTab(1),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.play_circle_outline, size: 16),
                    label: const Text('Automation'),
                    onPressed: () => onNavigateTab(2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.monitor_outlined, size: 16),
                    label: const Text('Live Stream'),
                    onPressed: () => onNavigateTab(3),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Recent Workspaces Header
            Row(
              children: [
                const Text(
                  'Recent Workspaces',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => onNavigateTab(1),
                  child: const Text('View All', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Workspaces List
            if (projects.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: surfaceColor,
                  border: Border.all(color: borderColor),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.folder_open_outlined,
                      size: 32,
                      color: AppColors.lightTextMuted,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'No local projects yet.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () async {
                        final p = await ref
                            .read(projectsProvider.notifier)
                            .createSampleProject();
                        onOpenProject(p);
                      },
                      child: const Text('Create Sample Project'),
                    ),
                  ],
                ),
              )
            else
              ...projects.take(4).map((p) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    border: Border.all(color: borderColor),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 2,
                    ),
                    leading: const Icon(
                      Icons.folder,
                      color: AppColors.accentLight,
                      size: 20,
                    ),
                    title: Text(
                      p.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      '${p.totalFiles} files (${p.selectedCodeFilesCount} code)',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.lightTextMuted,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () => onOpenProject(p),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
