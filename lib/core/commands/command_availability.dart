class CommandAvailability {
  const CommandAvailability._({
    required this.visible,
    required this.enabled,
    this.reason,
  });

  const CommandAvailability.available() : this._(visible: true, enabled: true);

  const CommandAvailability.disabled(String reason)
    : this._(visible: true, enabled: false, reason: reason);

  const CommandAvailability.hidden(String reason)
    : this._(visible: false, enabled: false, reason: reason);

  final bool visible;
  final bool enabled;
  final String? reason;
}
