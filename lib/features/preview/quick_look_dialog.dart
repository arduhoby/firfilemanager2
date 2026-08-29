import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/models/file_entry.dart';
import '../../core/theme/glass_container.dart';
import '../file_operations/file_operations_state.dart';

class QuickLookDialog extends ConsumerStatefulWidget {
  const QuickLookDialog({
    required this.entry,
    required this.providerId,
    super.key,
  });

  final FileEntry entry;
  final String providerId;

  @override
  ConsumerState<QuickLookDialog> createState() => _QuickLookDialogState();
}

class _QuickLookDialogState extends ConsumerState<QuickLookDialog> {
  String? _textContent;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    if (widget.providerId != 'local') {
      setState(() => _isLoading = false);
      return;
    }

    final ext = widget.entry.name.split('.').last.toLowerCase();
    final textExtensions = ['txt', 'md', 'json', 'yaml', 'yml', 'xml', 'csv', 'dart', 'js', 'html', 'css', 'py'];
    
    if (textExtensions.contains(ext)) {
      try {
        final file = File(widget.entry.path);
        // Only read up to 100KB to avoid freezing
        final size = await file.length();
        if (size > 100 * 1024) {
          _textContent = 'File is too large to preview (Max 100KB).';
        } else {
          _textContent = await file.readAsString();
        }
      } catch (e) {
        _textContent = 'Could not read file: $e';
      }
    }
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildContent(ThemeData theme) {
    if (widget.entry.isDirectory) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder, size: 100, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(widget.entry.name, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('Directory', style: theme.textTheme.bodyMedium),
          ],
        ),
      );
    }

    final ext = widget.entry.name.split('.').last.toLowerCase();
    final imageExtensions = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'];
    
    if (imageExtensions.contains(ext)) {
      if (widget.providerId == 'local') {
        return Center(
          child: Image.file(
            File(widget.entry.path),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, size: 64),
          ),
        );
      } else {
        return Center(child: Text('Image preview not supported for remote files yet.'));
      }
    }

    if (_textContent != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          _textContent!,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontFamily: 'monospace',
          ),
        ),
      );
    }

    // Fallback for unsupported types
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file, size: 100, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(widget.entry.name, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text('${widget.entry.size} bytes', style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): () => Navigator.of(context).pop(),
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop(),
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 800,
              maxHeight: 600,
            ),
            child: GlassContainer(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: theme.dividerColor)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.entry.name,
                            style: theme.textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.of(context).pop(),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                  // Content
                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _buildContent(theme),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
