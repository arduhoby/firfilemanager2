import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../file_operations/file_operations_state.dart';
import '../shell_adaptive/panel_controller.dart';
import 'bookmark_repository.dart';

class BookmarksMenuIcon extends ConsumerWidget {
  final PanelId side;

  const BookmarksMenuIcon({required this.side, super.key});

  void _showEditDialog(BuildContext context, WidgetRef ref, Bookmark bookmark) {
    final nameController = TextEditingController(text: bookmark.name);
    final pathController = TextEditingController(text: bookmark.path);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Favoriyi Düzenle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'İsim'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: pathController,
                decoration: const InputDecoration(labelText: 'Yol (Path)'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () {
                final newName = nameController.text.trim();
                final newPath = pathController.text.trim();
                if (newName.isNotEmpty && newPath.isNotEmpty) {
                  ref
                      .read(bookmarkRepositoryProvider.notifier)
                      .updateBookmark(bookmark.id, newName, newPath);
                  Navigator.pop(context);
                }
              },
              child: const Text('Kaydet'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarks = ref.watch(bookmarkRepositoryProvider);
    final panelState = ref.watch(panelStateProvider(side));
    final currentPath = panelState.activeTab.currentPath;
    final isBookmarked = bookmarks.any((b) => b.path == currentPath);
    final theme = Theme.of(context);

    return PopupMenuButton<String>(
      icon: Icon(
        isBookmarked ? Icons.star : Icons.star_border,
        size: 18,
        color: isBookmarked ? Colors.amber : null,
      ),
      tooltip: 'Bookmarks',
      offset: const Offset(0, 30),
      onSelected: (value) {
        if (value == '__toggle__') {
          ref
              .read(bookmarkRepositoryProvider.notifier)
              .toggleBookmark(currentPath);
        } else if (value.isNotEmpty) {
          ref.read(panelControllerProvider.notifier).navigate(side, value);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: '__toggle__',
          child: Row(
            children: [
              Icon(
                isBookmarked ? Icons.star_border : Icons.star,
                size: 18,
                color: isBookmarked ? null : Colors.amber,
              ),
              const SizedBox(width: 8),
              Text(
                isBookmarked
                    ? 'Remove from Bookmarks'
                    : 'Bookmark Current Directory',
              ),
            ],
          ),
        ),
        if (bookmarks.isNotEmpty) const PopupMenuDivider(),
        ...bookmarks.map(
          (bookmark) => PopupMenuItem(
            value: bookmark.path,
            child: Row(
              children: [
                Icon(Icons.folder, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    bookmark.name,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 16),
                  onPressed: () {
                    Navigator.pop(context); // Close the popup menu
                    _showEditDialog(context, ref, bookmark);
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                  onPressed: () {
                    Navigator.pop(context); // Close the popup menu
                    ref
                        .read(bookmarkRepositoryProvider.notifier)
                        .removeBookmark(bookmark.id);
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
