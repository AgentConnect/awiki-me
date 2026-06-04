import 'package:flutter/widgets.dart';

const bool awikiE2eEnabled = bool.fromEnvironment('AWIKI_E2E');

String? e2eIdentifier(String? identifier) {
  if (!awikiE2eEnabled || identifier == null || identifier.isEmpty) {
    return null;
  }
  return identifier;
}

String e2eMessageIdentifier(String content) {
  final normalized = content
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return 'e2e-message-${normalized.isEmpty ? 'empty' : normalized}';
}

Widget e2eSemantics({
  required Widget child,
  String? identifier,
  String? label,
  bool? button,
  bool? enabled,
  bool? textField,
}) {
  final effectiveIdentifier = e2eIdentifier(identifier);
  if (effectiveIdentifier == null &&
      label == null &&
      button == null &&
      enabled == null &&
      textField == null) {
    return child;
  }
  return Semantics(
    identifier: effectiveIdentifier,
    label: label,
    button: button,
    enabled: enabled,
    textField: textField,
    child: child,
  );
}

class E2eMarker extends StatelessWidget {
  const E2eMarker(this.identifier, {super.key});

  final String identifier;

  @override
  Widget build(BuildContext context) {
    if (!awikiE2eEnabled) {
      return const SizedBox.shrink();
    }
    return Semantics(
      identifier: identifier,
      label: identifier,
      child: const SizedBox(width: 1, height: 1),
    );
  }
}
