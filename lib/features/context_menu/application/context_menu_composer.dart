import '../../../core/commands/command_context.dart';
import '../../../core/commands/command_id.dart';
import '../../../core/commands/command_registry.dart';

enum ContextMenuLocation { item, background }

enum ContextMenuGroup {
  open,
  clipboard,
  mutation,
  archive,
  sharing,
  view,
  information,
}

class ContextMenuDefinition {
  const ContextMenuDefinition({
    required this.commandId,
    required this.location,
    required this.group,
    required this.labelKey,
    required this.iconKey,
    this.order = 0,
    this.destructive = false,
  });

  final CommandId commandId;
  final ContextMenuLocation location;
  final ContextMenuGroup group;
  final String labelKey;
  final String iconKey;
  final int order;
  final bool destructive;
}

class ContextMenuEntry {
  const ContextMenuEntry({
    required this.definition,
    required this.enabled,
    this.disabledReason,
  });

  final ContextMenuDefinition definition;
  final bool enabled;
  final String? disabledReason;
}

class ContextMenuComposer {
  const ContextMenuComposer({
    required CommandRegistry registry,
    required List<ContextMenuDefinition> definitions,
  }) : _registry = registry,
       _definitions = definitions;

  final CommandRegistry _registry;
  final List<ContextMenuDefinition> _definitions;

  List<ContextMenuEntry> compose({
    required ContextMenuLocation location,
    required CommandContext context,
  }) {
    final entries = <ContextMenuEntry>[];
    for (final definition in _definitions) {
      if (definition.location != location) continue;
      final availability = _registry
          .resolve(definition.commandId)
          .evaluate(context);
      if (!availability.visible) continue;
      entries.add(
        ContextMenuEntry(
          definition: definition,
          enabled: availability.enabled,
          disabledReason: availability.reason,
        ),
      );
    }
    entries.sort((left, right) {
      final group = left.definition.group.index.compareTo(
        right.definition.group.index,
      );
      return group != 0
          ? group
          : left.definition.order.compareTo(right.definition.order);
    });
    return List<ContextMenuEntry>.unmodifiable(entries);
  }
}
