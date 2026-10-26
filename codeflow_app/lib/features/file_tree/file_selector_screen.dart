import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../models/project.dart';
import '../../models/source_file.dart';
import 'file_tree_widget.dart';

class FileSelectorScreen extends ConsumerStatefulWidget {
  final Project project;
  final VoidCallback onProceedToAutomation;

  const FileSelectorScreen({
    super.key,
    required this.project,
    required this.onProceedToAutomation,
  });

  @override
  ConsumerState<FileSelectorScreen> createState() => _FileSelectorScreenState();
}

class _FileSelectorScreenState extends ConsumerState<FileSelectorScreen> {
  late Project _project;

  @override
  void initState() {
    super.initState();
    _project = widget.project;
  }

  void _onSelectionChanged(List<SourceFile> updatedFiles) {
    setState(() {
      _project = _project.copyWith(files: updatedFiles);
    });
    ref.read(projectsProvider.notifier).addProject(_project);
    ref.read(selectedProjectProvider.notifier).state = _project;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark
        ? AppColors.darkSurface
        : AppColors.lightSurface;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    final selectedCount = _project.selectedFilesCount;

    return Scaffold(
      appBar: AppBar(
        title: Text(_project.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.play_arrow, size: 22),
            tooltip: 'Run Automation',
            onPressed: selectedCount > 0 ? widget.onProceedToAutomation : null,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: FileTreeWidget(
                files: _project.files,
                onSelectionChanged: _onSelectionChanged,
              ),
            ),
            // Bottom Action Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: surfaceColor,
                border: Border(top: BorderSide(color: borderColor)),
              ),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$selectedCount files selected',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${_project.selectedCodeFilesCount} code files',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.lightTextMuted,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Automate Workflow'),
                    onPressed: selectedCount > 0
                        ? () {
                            ref.read(selectedProjectProvider.notifier).state =
                                _project;
                            widget.onProceedToAutomation();
                          }
                        : null,
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
