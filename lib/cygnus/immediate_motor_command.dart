/// Strict local shortcut: only a complete immediate imperative may actuate.
class ImmediateMotorCommand {
  const ImmediateMotorCommand(this.motor, this.enabled);
  final int? motor;
  final bool enabled;
  static ImmediateMotorCommand? parse(String text) {
    final value = text
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[.!]+$'), '');
    const target =
        r'(?:motor\s*([123])|([123])\s*motor|(first|second|third)\s+motor|(all|ella|ellaa|yella)\s+(?:the\s+)?motors?)';
    final targetFirst = RegExp(
      '^(?:please )?$target(?: (?:ah|va|ai|aiyum))? (on|off|start|stop)(?: (?:pannu|pannunga|pannuda|now|please))?\$',
    ).firstMatch(value);
    if (targetFirst != null) {
      return _create(
        targetFirst.group(1) ?? targetFirst.group(2),
        targetFirst.group(3),
        targetFirst.group(5)!,
      );
    }
    final actionFirst = RegExp(
      '^(?:please )?(?:switch |turn )?(on|off|start|stop) (?:the )?$target(?: (?:now|please))?\$',
    ).firstMatch(value);
    if (actionFirst == null) return null;
    return _create(
      actionFirst.group(2) ?? actionFirst.group(3),
      actionFirst.group(4),
      actionFirst.group(1)!,
    );
  }

  static ImmediateMotorCommand _create(
    String? digit,
    String? ordinal,
    String action,
  ) => ImmediateMotorCommand(
    digit != null
        ? int.parse(digit)
        : switch (ordinal) {
            'first' => 1,
            'second' => 2,
            'third' => 3,
            _ => null,
          },
    const {'on', 'start'}.contains(action),
  );
}
