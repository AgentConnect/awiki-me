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
  ShellDestination.contacts,
  ShellDestination.agents,
  ShellDestination.profile,
];

const List<ShellDestination> compactContentDestinations = <ShellDestination>[
  ...compactShellDestinations,
  ShellDestination.settings,
];

const List<ShellDestination> expandedShellDestinations = <ShellDestination>[
  ShellDestination.messages,
  ShellDestination.agents,
  ShellDestination.contacts,
  ShellDestination.tasks,
  ShellDestination.workbench,
  ShellDestination.settings,
];

class ShellNavigationController extends StateNotifier<ShellDestination> {
  ShellNavigationController({
    ShellDestination initialDestination = ShellDestination.messages,
  }) : _lastCompactPrimaryDestination =
           compactShellDestinations.contains(initialDestination)
           ? initialDestination
           : ShellDestination.messages,
       _lastDesktopDestination =
           expandedShellDestinations.contains(initialDestination)
           ? initialDestination
           : ShellDestination.messages,
       super(initialDestination);

  ShellDestination _lastCompactPrimaryDestination;
  ShellDestination _lastDesktopDestination;
  ShellDestination? _previousDestination;

  ShellDestination get lastPrimaryDestination => _lastCompactPrimaryDestination;

  ShellDestination get lastCompactPrimaryDestination =>
      _lastCompactPrimaryDestination;

  ShellDestination get lastDesktopDestination => _lastDesktopDestination;

  void select(ShellDestination destination) {
    _select(destination, updateCompact: true, updateDesktop: true);
  }

  void selectCompact(ShellDestination destination) {
    _select(destination, updateCompact: true, updateDesktop: false);
  }

  void selectExpanded(ShellDestination destination) {
    if (!expandedShellDestinations.contains(destination)) {
      return;
    }
    _select(destination, updateCompact: false, updateDesktop: true);
  }

  void selectForLayout(ShellDestination destination, {required bool expanded}) {
    if (expanded) {
      selectExpanded(destination);
    } else {
      selectCompact(destination);
    }
  }

  void _select(
    ShellDestination destination, {
    required bool updateCompact,
    required bool updateDesktop,
  }) {
    if (destination == state) {
      return;
    }
    _previousDestination = state;
    if (updateCompact && compactShellDestinations.contains(destination)) {
      _lastCompactPrimaryDestination = destination;
    }
    if (updateDesktop && expandedShellDestinations.contains(destination)) {
      _lastDesktopDestination = destination;
    }
    state = destination;
  }

  void reconcileFor(bool expanded) {
    final available = expanded
        ? expandedShellDestinations
        : compactContentDestinations;
    if (!available.contains(state)) {
      state = expanded
          ? _lastDesktopDestination
          : _lastCompactPrimaryDestination;
    }
  }

  ShellDestination resolvedFor(bool expanded) {
    final available = expanded
        ? expandedShellDestinations
        : compactContentDestinations;
    if (available.contains(state)) {
      return state;
    }
    return expanded ? _lastDesktopDestination : _lastCompactPrimaryDestination;
  }

  void backFromSecondary() {
    if (state == ShellDestination.settings &&
        compactShellDestinations.contains(_previousDestination)) {
      selectCompact(_previousDestination!);
      return;
    }
    selectCompact(_lastCompactPrimaryDestination);
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
