import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppLifecycleController extends StateNotifier<AppLifecycleState> {
  AppLifecycleController() : super(AppLifecycleState.resumed);

  void setLifecycle(AppLifecycleState state) {
    if (this.state == state) {
      return;
    }
    this.state = state;
  }
}

final appLifecycleProvider =
    StateNotifierProvider<AppLifecycleController, AppLifecycleState>(
  (ref) => AppLifecycleController(),
);
