import 'dart:convert';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../core/persistence/app_preferences.dart';

part 'bookmark_repository.g.dart';

const _kBookmarksKey = 'fir_bookmarks';

class Bookmark {
  final String id;
  final String name;
  final String path;

  Bookmark({required this.id, required this.name, required this.path});

  factory Bookmark.fromJson(Map<String, dynamic> json) {
    return Bookmark(
      id: json['id'] as String? ?? json['path'] as String,
      name: json['name'] as String,
      path: json['path'] as String,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'path': path};
}

@Riverpod(keepAlive: true)
class BookmarkRepository extends _$BookmarkRepository {
  @override
  List<Bookmark> build() {
    _load();
    return [];
  }

  Future<void> _load() async {
    final prefs = await AppPreferences.getInstance();
    final items = prefs.getStringList(_kBookmarksKey) ?? [];

    final parsed = <Bookmark>[];
    for (final item in items) {
      if (item.startsWith('{')) {
        try {
          parsed.add(
            Bookmark.fromJson(
              Map<String, dynamic>.from(jsonDecode(item) as Map),
            ),
          );
        } catch (_) {}
      } else {
        // Legacy path-only bookmark
        final name = item
            .split('/')
            .lastWhere((part) => part.isNotEmpty, orElse: () => item);
        parsed.add(Bookmark(id: item, name: name, path: item));
      }
    }
    state = parsed;
  }

  Future<void> addBookmark(String path) async {
    if (state.any((b) => b.path == path)) return;

    final name = path
        .split('/')
        .lastWhere((part) => part.isNotEmpty, orElse: () => path);
    final newBookmark = Bookmark(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      path: path,
    );

    final newState = [...state, newBookmark];
    state = newState;
    await _save(newState);
  }

  Future<void> removeBookmark(String id) async {
    final newState = state.where((p) => p.id != id).toList();
    if (newState.length == state.length) return;

    state = newState;
    await _save(newState);
  }

  Future<void> updateBookmark(String id, String newName, String newPath) async {
    final newState = state.map((b) {
      if (b.id == id) {
        return Bookmark(id: id, name: newName, path: newPath);
      }
      return b;
    }).toList();
    state = newState;
    await _save(newState);
  }

  Future<void> toggleBookmark(String path) async {
    final existing = state.where((b) => b.path == path).firstOrNull;
    if (existing != null) {
      await removeBookmark(existing.id);
    } else {
      await addBookmark(path);
    }
  }

  Future<void> _save(List<Bookmark> items) async {
    final prefs = await AppPreferences.getInstance();
    final stringList = items.map((b) => jsonEncode(b.toJson())).toList();
    await prefs.setStringList(_kBookmarksKey, stringList);
  }
}
