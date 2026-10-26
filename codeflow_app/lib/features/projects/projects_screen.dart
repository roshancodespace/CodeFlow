import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../models/project.dart';

class ProjectsScreen extends ConsumerStatefulWidget {
  final void Function(Project project) onSelectProject;

  const ProjectsScreen({super.key, required this.onSelectProject});

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  bool _isImporting = false;
  String? _importProgressMessage;

  Future<void> _showGitHubImportDialog() async {
    final controller = TextEditingController(text: 'flutter/samples');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import GitHub Repository', style: TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter public GitHub repository (e.g. "torvalds/subsurface" or full URL):',
              style: TextStyle(fontSize: 12, color: AppColors.lightTextSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'owner/repo',
                prefixIcon: Icon(Icons.code, size: 18),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Download & Import'),
          ),
        ],
      ),
    );

    if (confirmed == true && controller.text.trim().isNotEmpty) {
      setState(() {
        _isImporting = true;
        _importProgressMessage = 'Connecting to GitHub...';
      });

      try {
        final manager = ref.read(projectManagerProvider);
        final proj = await manager.importFromGitHub(
          repoUrlOrSlug: controller.text.trim(),
          onProgress: (msg) {
            setState(() => _importProgressMessage = msg);
          },
        );

        ref.read(projectsProvider.notifier).loadProjects();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Successfully imported ${proj.name}')),
          );
          widget.onSelectProject(proj);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Import failed: $e'),
              backgroundColor: AppColors.statusError,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isImporting = false;
            _importProgressMessage = null;
          });
        }
      }
    }
  }

  Future<void> _confirmDelete(Project project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Project', style: TextStyle(fontSize: 16)),
        content: Text('Are you sure you want to delete "${project.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.statusError),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(projectsProvider.notifier).deleteProject(project.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted ${project.name}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final projects = ref.watch(projectsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Projects & Workspaces'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, size: 20),
            tooltip: 'Import Options',
            onPressed: () => _showImportBottomSheet(context),
          ),
        ],
      ),
      body: SafeArea(
        child: _isImporting
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(strokeWidth: 2.5),
                      const SizedBox(height: 16),
                      Text(
                        _importProgressMessage ?? 'Importing...',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            : projects.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.folder_open_outlined,
                              size: 40, color: AppColors.lightTextMuted),
                          const SizedBox(height: 12),
                          const Text(
                            'No projects in workspace.',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppColors.lightTextSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Import from a GitHub repository or create a sample starter project.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.lightTextMuted,
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () => _showImportBottomSheet(context),
                            child: const Text('Import Project'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: projects.length,
                    itemBuilder: (context, index) {
                      final p = projects[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: surfaceColor,
                          border: Border.all(color: borderColor),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                          leading: const Icon(Icons.folder,
                              color: AppColors.accentLight, size: 24),
                          title: Text(
                            p.name,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${p.totalFiles} files • ${p.selectedCodeFilesCount} code files • ${_formatBytes(p.totalSizeInBytes)}',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.lightTextMuted),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 18, color: AppColors.lightTextMuted),
                                tooltip: 'Delete Project',
                                onPressed: () => _confirmDelete(p),
                              ),
                              const Icon(Icons.chevron_right, size: 18),
                            ],
                          ),
                          onTap: () => widget.onSelectProject(p),
                        ),
                      );
                    },
                  ),
      ),
    );
  }

  void _showImportBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.code, size: 20),
                title: const Text('Import from Public GitHub Repository',
                    style: TextStyle(fontSize: 13)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showGitHubImportDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.auto_awesome_outlined, size: 20),
                title: const Text('Create Sample Starter Workspace',
                    style: TextStyle(fontSize: 13)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final p = await ref
                      .read(projectsProvider.notifier)
                      .createSampleProject();
                  widget.onSelectProject(p);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
