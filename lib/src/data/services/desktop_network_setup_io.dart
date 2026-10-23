import 'dart:io';
import 'app_http_client_io.dart';

Future<String?>? _trust;
Future<String?> desktopNetworkCaBundle() => _trust ??= Platform.isWindows
    ? prepareWindowsNetworkCaBundle()
    : Future.value(null);
