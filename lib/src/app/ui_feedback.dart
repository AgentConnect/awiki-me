import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_message.dart';

class UiFeedbackEvent {
  const UiFeedbackEvent({
    required this.id,
    required this.message,
    required this.danger,
  });

  final int id;
  final AppMessage message;
  final bool danger;
}

class UiFeedbackController extends StateNotifier<UiFeedbackEvent?> {
  UiFeedbackController() : super(null);

  int _seed = 0;

  void showInfo(AppMessage message) {
    state = UiFeedbackEvent(id: ++_seed, message: message, danger: false);
  }

  void showError(AppMessage message) {
    state = UiFeedbackEvent(id: ++_seed, message: message, danger: true);
  }
}

final uiFeedbackProvider =
    StateNotifierProvider<UiFeedbackController, UiFeedbackEvent?>(
      (ref) => UiFeedbackController(),
    );
