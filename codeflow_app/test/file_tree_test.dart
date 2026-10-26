import 'package:flutter_test/flutter_test.dart';
import 'package:codeflow_app/models/source_file.dart';
import 'package:codeflow_app/features/file_tree/file_tree_widget.dart';

void main() {
  group('FileTree & SourceFile Tests', () {
    test('isCodeFile correctly identifies code file extensions', () {
      const dartFile = SourceFile(
        path: '/a/b.dart',
        relativePath: 'lib/b.dart',
        sizeInBytes: 100,
        extension: '.dart',
      );
      expect(dartFile.isCodeFile, isTrue);

      const pyFile = SourceFile(
        path: '/a/main.py',
        relativePath: 'main.py',
        sizeInBytes: 200,
        extension: '.py',
      );
      expect(pyFile.isCodeFile, isTrue);

      const pngFile = SourceFile(
        path: '/a/img.png',
        relativePath: 'assets/img.png',
        sizeInBytes: 5000,
        extension: '.png',
      );
      expect(pngFile.isCodeFile, isFalse);

      const dirFile = SourceFile(
        path: '/a/dir',
        relativePath: 'dir',
        sizeInBytes: 0,
        extension: '',
        isDirectory: true,
      );
      expect(dirFile.isCodeFile, isFalse);
    });

    test('FileTreeNode selectionState computes tri-state correctly', () {
      final f1 = SourceFile(
        path: 'dir/f1.dart',
        relativePath: 'dir/f1.dart',
        sizeInBytes: 10,
        extension: '.dart',
        isSelected: true,
      );
      final f2 = SourceFile(
        path: 'dir/f2.dart',
        relativePath: 'dir/f2.dart',
        sizeInBytes: 20,
        extension: '.dart',
        isSelected: false,
      );

      final node1 = FileTreeNode(
        name: 'f1.dart',
        relativePath: 'dir/f1.dart',
        isDirectory: false,
        file: f1,
      );
      final node2 = FileTreeNode(
        name: 'f2.dart',
        relativePath: 'dir/f2.dart',
        isDirectory: false,
        file: f2,
      );

      final dirNode = FileTreeNode(
        name: 'dir',
        relativePath: 'dir',
        isDirectory: true,
        children: [node1, node2],
      );

      // One selected, one unselected -> null (indeterminate)
      expect(dirNode.selectionState, isNull);

      // Select both -> true
      final f2Selected = f2.copyWith(isSelected: true);
      final node2Selected = FileTreeNode(
        name: 'f2.dart',
        relativePath: 'dir/f2.dart',
        isDirectory: false,
        file: f2Selected,
      );
      final dirNodeAll = FileTreeNode(
        name: 'dir',
        relativePath: 'dir',
        isDirectory: true,
        children: [node1, node2Selected],
      );
      expect(dirNodeAll.selectionState, isTrue);
    });
  });
}
