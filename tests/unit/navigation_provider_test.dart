import 'package:awiki_me/src/presentation/app_shell/providers/navigation_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'compact destinations contain exactly the three primary destinations',
    () {
      expect(compactShellDestinations, const <ShellDestination>[
        ShellDestination.messages,
        ShellDestination.agents,
        ShellDestination.contacts,
      ]);
    },
  );

  test('expanded destinations contain all seven destinations', () {
    expect(expandedShellDestinations, ShellDestination.values);
  });

  test(
    'compact content also allows profile and settings as secondary pages',
    () {
      expect(compactContentDestinations, const <ShellDestination>[
        ShellDestination.messages,
        ShellDestination.agents,
        ShellDestination.contacts,
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

  test(
    'secondary back returns profile to settings and then to last primary',
    () {
      final controller = ShellNavigationController();
      addTearDown(controller.dispose);

      controller.select(ShellDestination.contacts);
      controller.select(ShellDestination.settings);
      controller.select(ShellDestination.profile);

      controller.backFromSecondary();
      expect(_currentDestination(controller), ShellDestination.settings);

      controller.backFromSecondary();
      expect(_currentDestination(controller), ShellDestination.contacts);
    },
  );

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
