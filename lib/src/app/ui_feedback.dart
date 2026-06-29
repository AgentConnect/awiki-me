import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_message.dart';

class UiFeedbackEvent {
  const UiFeedbackEvent({
    required this.id,
    required this.message,
    required this.danger,
    this.detail,
  });

  final int id;
  final AppMessage message;
  final bool danger;
  final String? detail;
}

class UiFeedbackController extends StateNotifier<UiFeedbackEvent?> {
  UiFeedbackController() : super(null);

  int _seed = 0;

  void showInfo(AppMessage message, {String? detail}) {
    state = UiFeedbackEvent(
      id: ++_seed,
      message: message,
      danger: false,
      detail: detail,
    );
  }

  void showError(AppMessage message, {String? detail}) {
    state = UiFeedbackEvent(
      id: ++_seed,
      message: message,
      danger: true,
      detail: detail,
    );
  }
}

final uiFeedbackProvider =
    StateNotifierProvider<UiFeedbackController, UiFeedbackEvent?>(
      (ref) => UiFeedbackController(),
    );
