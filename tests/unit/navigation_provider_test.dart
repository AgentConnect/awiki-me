import 'package:awiki_me/src/presentation/app_shell/providers/navigation_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'compact destinations contain the four ordered primary destinations',
    () {
      expect(compactShellDestinations, const <ShellDestination>[
        ShellDestination.messages,
        ShellDestination.contacts,
        ShellDestination.agents,
        ShellDestination.profile,
      ]);
    },
  );

  test('expanded destinations exclude profile from desktop rail content', () {
    expect(expandedShellDestinations, const <ShellDestination>[
      ShellDestination.messages,
      ShellDestination.agents,
      ShellDestination.contacts,
      ShellDestination.tasks,
      ShellDestination.workbench,
      ShellDestination.settings,
    ]);
  });

  test(
    'compact content includes four primary pages and secondary settings',
    () {
      expect(compactContentDestinations, const <ShellDestination>[
        ShellDestination.messages,
        ShellDestination.contacts,
        ShellDestination.agents,
        ShellDestination.profile,
        ShellDestination.settings,
      ]);
    },
  );

  test('navigation defaults to messages and select changes typed state', () {
    final controller = ShellNavigationController();
    addTearDown(controller.dispose);

    expect(_currentDestination(controller), ShellDestination.messages);

    controller.select(ShellDestination.workbench);

    expect(_currentDestination(controller), ShellDestination.workbench);
  });

  test('compact reconciliation preserves every available content page', () {
    for (final destination in compactContentDestinations) {
      final controller = ShellNavigationController(
        initialDestination: destination,
      );

      controller.reconcileFor(false);

      expect(
        _currentDestination(controller),
        destination,
        reason: '$destination',
      );
      controller.dispose();
    }
  });

  test(
    'compact reconciliation falls desktop-only destinations back to last primary page',
    () {
      for (final desktopOnly in const <ShellDestination>[
        ShellDestination.tasks,
        ShellDestination.workbench,
      ]) {
        final controller = ShellNavigationController();
        controller.select(ShellDestination.contacts);
        controller.select(desktopOnly);

        controller.reconcileFor(false);

        expect(
          _currentDestination(controller),
          ShellDestination.contacts,
          reason: '$desktopOnly',
        );
        controller.dispose();
      }
    },
  );

  test('expanded reconciliation preserves every destination', () {
    for (final destination in expandedShellDestinations) {
      final controller = ShellNavigationController(
        initialDestination: destination,
      );

      controller.reconcileFor(true);

      expect(
        _currentDestination(controller),
        destination,
        reason: '$destination',
      );
      controller.dispose();
    }
  });

  test('settings back returns to the compact primary page that opened it', () {
    final controller = ShellNavigationController();
    addTearDown(controller.dispose);

    controller.selectCompact(ShellDestination.contacts);
    controller.selectCompact(ShellDestination.settings);

    controller.backFromSecondary();
    expect(_currentDestination(controller), ShellDestination.contacts);
  });

  test('compact profile maps to the last valid desktop content page', () {
    final controller = ShellNavigationController();
    addTearDown(controller.dispose);

    controller.selectExpanded(ShellDestination.agents);
    controller.selectCompact(ShellDestination.profile);

    expect(controller.resolvedFor(true), ShellDestination.agents);
    controller.reconcileFor(true);
    expect(_currentDestination(controller), ShellDestination.agents);
  });

  test('desktop selection cannot select profile as invisible content', () {
    final controller = ShellNavigationController();
    addTearDown(controller.dispose);

    controller.selectExpanded(ShellDestination.profile);

    expect(_currentDestination(controller), ShellDestination.messages);
    expect(controller.lastDesktopDestination, ShellDestination.messages);
  });

  test('provider exposes typed destination state', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(shellDestinationProvider.notifier)
        .select(ShellDestination.settings);

    expect(container.read(shellDestinationProvider), ShellDestination.settings);
  });
}

ShellDestination _currentDestination(ShellNavigationController controller) {
  late ShellDestination destination;
  final removeListener = controller.addListener((value) {
    destination = value;
  });
  removeListener();
  return destination;
}
