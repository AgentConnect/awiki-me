import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ShellDestination {
  messages,
  agents,
  contacts,
  profile,
  tasks,
  workbench,
  settings,
}

const List<ShellDestination> compactShellDestinations = <ShellDestination>[
  ShellDestination.messages,
  ShellDestination.agents,
  ShellDestination.contacts,
];

const List<ShellDestination> compactContentDestinations = <ShellDestination>[
  ...compactShellDestinations,
  ShellDestination.profile,
  ShellDestination.settings,
];

const List<ShellDestination> expandedShellDestinations = <ShellDestination>[
  ShellDestination.messages,
  ShellDestination.agents,
  ShellDestination.contacts,
  ShellDestination.profile,
  ShellDestination.tasks,
  ShellDestination.workbench,
  ShellDestination.settings,
];

class ShellNavigationController extends StateNotifier<ShellDestination> {
  ShellNavigationController({
    ShellDestination initialDestination = ShellDestination.messages,
  }) : _lastPrimaryDestination =
           compactShellDestinations.contains(initialDestination)
           ? initialDestination
           : ShellDestination.messages,
       super(initialDestination);

  ShellDestination _lastPrimaryDestination;
  ShellDestination? _previousDestination;

  ShellDestination get lastPrimaryDestination => _lastPrimaryDestination;

  void select(ShellDestination destination) {
    if (destination == state) {
      return;
    }
    _previousDestination = state;
    if (compactShellDestinations.contains(destination)) {
      _lastPrimaryDestination = destination;
    }
    state = destination;
  }

  void reconcileFor(bool expanded) {
    final available = expanded
        ? expandedShellDestinations
        : compactContentDestinations;
    if (!available.contains(state)) {
      select(_lastPrimaryDestination);
    }
  }

  ShellDestination resolvedFor(bool expanded) {
    final available = expanded
        ? expandedShellDestinations
        : compactContentDestinations;
    return available.contains(state) ? state : _lastPrimaryDestination;
  }

  void backFromSecondary() {
    if (state == ShellDestination.profile &&
        _previousDestination == ShellDestination.settings) {
      select(ShellDestination.settings);
      return;
    }
    select(_lastPrimaryDestination);
  }
}

final shellDestinationProvider =
    StateNotifierProvider<ShellNavigationController, ShellDestination>(
      (ref) => ShellNavigationController(),
    );

class AwikiShellNavigationScope extends InheritedWidget {
  const AwikiShellNavigationScope({super.key, required super.child});

  static bool isPresent(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AwikiShellNavigationScope>() !=
      null;

  @override
  bool updateShouldNotify(AwikiShellNavigationScope oldWidget) => false;
}
