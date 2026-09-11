import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../e2e/runner.dart';

Map<String, String> driverEnvironment(Map<String, String> parent) =>
    appPairDriverEnvironment(
      parent: parent,
      locale: 'en_US.UTF-8',
      flutterConfigPath: '/tmp/app-pair/driver-config',
    );

String route(String url, Map<String, String> environment) =>
    HttpClient.findProxyFromEnvironment(
      Uri.parse(url),
      environment: environment,
    );

void main() {
  const proxies = <String, String>{
    'HTTP_PROXY': 'http://127.0.0.1:7890',
    'HTTPS_PROXY': 'http://127.0.0.1:7890',
    'ALL_PROXY': 'socks5h://127.0.0.1:7890',
  };

  for (final host in ['127.0.0.1', 'localhost', '[::1]']) {
    test('VM Service HTTP upgrade connects directly to $host', () {
      expect(
        route('http://$host:8123/service/ws', driverEnvironment(proxies)),
        'DIRECT',
      );
    });
  }

  test('preserves proxy routing for external HTTP and HTTPS endpoints', () {
    final environment = driverEnvironment(proxies);
    expect(
      route('https://awiki.info/im/rpc', environment),
      'PROXY 127.0.0.1:7890',
    );
    expect(route('http://example.test/', environment), 'PROXY 127.0.0.1:7890');
    for (final entry in proxies.entries) {
      expect(environment[entry.key], entry.value);
    }
  });

  test('preserves effective existing exclusions and lower-case precedence', () {
    final parent = <String, String>{
      ...proxies,
      'NO_PROXY': 'awiki.info',
      'no_proxy': ' internal.test,127.0.0.1 ',
    };
    final environment = driverEnvironment(parent);
    expect(route('https://internal.test/', environment), 'DIRECT');
    expect(route('https://awiki.info/', environment), 'PROXY 127.0.0.1:7890');
    expect(environment['NO_PROXY'], environment['no_proxy']);
    expect(parent['NO_PROXY'], 'awiki.info');
    expect(parent['no_proxy'], ' internal.test,127.0.0.1 ');
  });

  test('preserves uppercase exclusions when lowercase is absent', () {
    final environment = driverEnvironment({
      ...proxies,
      'NO_PROXY': 'internal.test',
    });
    expect(route('https://internal.test/', environment), 'DIRECT');
    expect(route('http://localhost:8123/', environment), 'DIRECT');
  });

  test('empty lowercase exclusions still override the uppercase value', () {
    final environment = driverEnvironment({
      ...proxies,
      'NO_PROXY': 'awiki.info',
      'no_proxy': '',
    });
    expect(route('https://awiki.info/', environment), 'PROXY 127.0.0.1:7890');
    expect(route('http://localhost:8123/', environment), 'DIRECT');
  });

  test('keeps isolated Flutter configuration and is idempotent', () {
    final environment = driverEnvironment({
      ...proxies,
      'LANG': 'C',
      'XDG_CONFIG_HOME': '/original',
      'custom': 'preserved',
    });
    expect(environment['LANG'], 'en_US.UTF-8');
    expect(environment['LC_ALL'], 'en_US.UTF-8');
    expect(environment['XDG_CONFIG_HOME'], '/tmp/app-pair/driver-config');
    expect(environment['custom'], 'preserved');
    expect(driverEnvironment(environment), environment);
  });
}
