import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../models/source_file.dart';

/// File Tree Node for hierarchical directory navigation
class FileTreeNode {
  final String name;
  final String relativePath;
  final bool isDirectory;
  final SourceFile? file;
  final List<FileTreeNode> children;
  bool isExpanded;

  FileTreeNode({
    required this.name,
    required this.relativePath,
    required this.isDirectory,
    this.file,
    List<FileTreeNode>? children,
    this.isExpanded = false,
  }) : children = children ?? [];

  /// Check tri-state selection: true = all selected, false = none, null = partial
  bool? get selectionState {
    if (!isDirectory) {
      return file?.isSelected ?? false;
    }
    if (children.isEmpty) return false;

    int selectedCount = 0;
    int totalCount = 0;

    void countChildren(FileTreeNode node) {
      if (!node.isDirectory) {
        totalCount++;
        if (node.file?.isSelected ?? false) selectedCount++;
      } else {
        for (final child in node.children) {
          countChildren(child);
        }
      }
    }

    countChildren(this);
    if (totalCount == 0) return false;
    if (selectedCount == totalCount) return true;
    if (selectedCount == 0) return false;
    return null; // Indeterminate / Tri-state
  }
}

/// Flat, compact hierarchical file tree selector with search, badges, and bulk controls.
class FileTreeWidget extends StatefulWidget {
  final List<SourceFile> files;
  final void Function(List<SourceFile> updatedFiles) onSelectionChanged;

  const FileTreeWidget({
    super.key,
    required this.files,
    required this.onSelectionChanged,
  });

  @override
  State<FileTreeWidget> createState() => _FileTreeWidgetState();
}

class _FileTreeWidgetState extends State<FileTreeWidget> {
  late List<SourceFile> _currentFiles;
  String _searchFilter = '';
  final TextEditingController _searchController = TextEditingController();
  List<FileTreeNode> _rootNodes = [];

  @override
  void initState() {
    super.initState();
    _currentFiles = List.from(widget.files);
    _buildTree();
  }

  @override
  void didUpdateWidget(covariant FileTreeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.files != widget.files) {
      _currentFiles = List.from(widget.files);
      _buildTree();
    }
  }

  void _buildTree() {
    final Map<String, FileTreeNode> dirMap = {};
    final List<FileTreeNode> roots = [];

    // Filter files if search active
    final displayFiles = _searchFilter.isEmpty
        ? _currentFiles
        : _currentFiles.where((f) {
            return f.relativePath.toLowerCase().contains(_searchFilter.toLowerCase());
          }).toList();

    for (final sf in displayFiles) {
      final parts = sf.relativePath.split('/');
      String currentPath = '';

      FileTreeNode? parent;
      for (int i = 0; i < parts.length; i++) {
        final part = parts[i];
        final isLast = (i == parts.length - 1);
        currentPath = currentPath.isEmpty ? part : '$currentPath/$part';

        if (isLast && !sf.isDirectory) {
          final leaf = FileTreeNode(
            name: part,
            relativePath: sf.relativePath,
            isDirectory: false,
            file: sf,
          );
          if (parent != null) {
            parent.children.add(leaf);
          } else {
            roots.add(leaf);
          }
        } else {
          // Directory node
          if (!dirMap.containsKey(currentPath)) {
            final dirNode = FileTreeNode(
              name: part,
              relativePath: currentPath,
              isDirectory: true,
              isExpanded: _searchFilter.isNotEmpty, // Auto-expand when searching
            );
            dirMap[currentPath] = dirNode;
            if (parent != null) {
              parent.children.add(dirNode);
            } else {
              roots.add(dirNode);
            }
          }
          parent = dirMap[currentPath];
        }
      }
    }

    setState(() {
      _rootNodes = roots;
    });
  }

  void _toggleFileSelection(SourceFile file) {
    final idx = _currentFiles.indexWhere((f) => f.relativePath == file.relativePath);
    if (idx >= 0) {
      setState(() {
        _currentFiles[idx] = file.copyWith(isSelected: !file.isSelected);
        _buildTree();
      });
      widget.onSelectionChanged(_currentFiles);
    }
  }

  void _toggleDirectorySelection(FileTreeNode dirNode, bool select) {
    final targetPrefix = '${dirNode.relativePath}/';
    setState(() {
      for (int i = 0; i < _currentFiles.length; i++) {
        final f = _currentFiles[i];
        if (f.relativePath == dirNode.relativePath ||
            f.relativePath.startsWith(targetPrefix)) {
          _currentFiles[i] = f.copyWith(isSelected: select);
        }
      }
      _buildTree();
    });
    widget.onSelectionChanged(_currentFiles);
  }

  void _bulkSelectAll(bool select) {
    setState(() {
      for (int i = 0; i < _currentFiles.length; i++) {
        _currentFiles[i] = _currentFiles[i].copyWith(isSelected: select);
      }
      _buildTree();
    });
    widget.onSelectionChanged(_currentFiles);
  }

  void _selectCodeOnly() {
    setState(() {
      for (int i = 0; i < _currentFiles.length; i++) {
        final f = _currentFiles[i];
        _currentFiles[i] = f.copyWith(isSelected: f.isCodeFile);
      }
      _buildTree();
    });
    widget.onSelectionChanged(_currentFiles);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final selectedCount = _currentFiles.where((f) => !f.isDirectory && f.isSelected).length;
    final totalCount = _currentFiles.where((f) => !f.isDirectory).length;

    return Column(
      children: [
        // Search & Filter Input Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Filter files (e.g. .dart, service)...',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _searchFilter.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchFilter = '';
                          _buildTree();
                        });
                      },
                    )
                  : null,
            ),
            onChanged: (val) {
              setState(() {
                _searchFilter = val.trim();
                _buildTree();
              });
            },
          ),
        ),

        // Bulk Selection Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: borderColor),
              bottom: BorderSide(color: borderColor),
            ),
          ),
          child: Row(
            children: [
              Text(
                '$selectedCount of $totalCount selected',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => _bulkSelectAll(true),
                child: const Text('All', style: TextStyle(fontSize: 12)),
              ),
              TextButton(
                onPressed: _selectCodeOnly,
                child: const Text('Code Only', style: TextStyle(fontSize: 12)),
              ),
              TextButton(
                onPressed: () => _bulkSelectAll(false),
                child: const Text('None', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),

        // Tree List View
        Expanded(
          child: _rootNodes.isEmpty
              ? const Center(
                  child: Text(
                    'No matching files found.',
                    style: TextStyle(color: AppColors.lightTextMuted, fontSize: 13),
                  ),
                )
              : ListView.builder(
                  itemCount: _rootNodes.length,
                  itemBuilder: (context, index) {
                    return _buildTreeNodeRow(_rootNodes[index], 0);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTreeNodeRow(FileTreeNode node, int depth) {
    if (node.isDirectory) {
      final triState = node.selectionState;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () {
              setState(() {
                node.isExpanded = !node.isExpanded;
              });
            },
            child: Padding(
              padding: EdgeInsets.only(left: 12.0 + (depth * 16.0), top: 4, bottom: 4, right: 8),
              child: Row(
                children: [
                  Icon(
                    node.isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                    size: 18,
                    color: AppColors.lightTextMuted,
                  ),
                  const SizedBox(width: 4),
                  // Tri-state checkbox
                  Checkbox(
                    tristate: true,
                    value: triState,
                    onChanged: (bool? val) {
                      _toggleDirectorySelection(node, val == true);
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                  const Icon(Icons.folder_outlined, size: 16, color: AppColors.accentLight),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      node.name,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (node.isExpanded)
            ...node.children.map((child) => _buildTreeNodeRow(child, depth + 1)),
        ],
      );
    } else {
      // Leaf File Row
      final file = node.file!;
      return InkWell(
        onTap: () => _toggleFileSelection(file),
        child: Padding(
          padding: EdgeInsets.only(left: 12.0 + (depth * 16.0), top: 3, bottom: 3, right: 12),
          child: Row(
            children: [
              Checkbox(
                value: file.isSelected,
                onChanged: (_) => _toggleFileSelection(file),
                visualDensity: VisualDensity.compact,
              ),
              _buildExtensionBadge(file.extension),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  node.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: file.isSelected ? FontWeight.w500 : FontWeight.w400,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _formatFileSize(file.sizeInBytes),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.lightTextMuted,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildExtensionBadge(String ext) {
    Color badgeColor;
    String label = ext.startsWith('.') ? ext.substring(1).toUpperCase() : ext.toUpperCase();
    if (label.isEmpty) label = 'FILE';

    switch (ext.toLowerCase()) {
      case '.dart':
        badgeColor = AppColors.badgeDart;
        break;
      case '.py':
        badgeColor = AppColors.badgePython;
        break;
      case '.kt':
      case '.java':
        badgeColor = AppColors.badgeKotlin;
        break;
      case '.json':
      case '.yaml':
      case '.yml':
        badgeColor = AppColors.badgeJson;
        break;
      case '.md':
      case '.txt':
        badgeColor = AppColors.badgeMarkdown;
        break;
      default:
        badgeColor = AppColors.badgeGeneric;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: badgeColor.withAlpha(30),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: badgeColor.withAlpha(80), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: badgeColor,
        ),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
