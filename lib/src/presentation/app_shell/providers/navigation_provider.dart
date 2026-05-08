import 'package:flutter_riverpod/flutter_riverpod.dart';

class ShellTabController extends StateNotifier<int> {
  ShellTabController() : super(0);

  void setTab(int index) {
    state = index;
  }
}

final shellTabProvider = StateNotifierProvider<ShellTabController, int>(
  (ref) => ShellTabController(),
);
