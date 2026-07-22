import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void expectWindowsHeaderBefore(String path, List<String> dependentHeaders) {
  final source = File(path).readAsStringSync();
  final windowsHeader = source.indexOf('#include <windows.h>');
  expect(windowsHeader, greaterThanOrEqualTo(0), reason: path);
  for (final header in dependentHeaders) {
    final dependentHeader = source.indexOf('#include <$header>');
    expect(
      dependentHeader,
      greaterThan(windowsHeader),
      reason: '$path: $header',
    );
  }
}

void main() {
  test('Windows SDK headers follow the required base-header order', () {
    expectWindowsHeaderBefore('windows/runner/desktop_shell.h', <String>[
      'shellapi.h',
      'shobjidl.h',
    ]);
    expectWindowsHeaderBefore('windows/runner/desktop_shell.cpp', <String>[
      'shellapi.h',
      'shlobj.h',
      'shobjidl.h',
    ]);
    expectWindowsHeaderBefore('windows/runner/main.cpp', <String>[
      'shellapi.h',
      'shobjidl.h',
    ]);
    expectWindowsHeaderBefore('windows/runner/scope_secret_store.cpp', <String>[
      'wincred.h',
      'wincrypt.h',
    ]);
    expectWindowsHeaderBefore(
      'windows/runner/windows_region_capture.cpp',
      <String>['windowsx.h', 'wincodec.h'],
    );

    final scopeSecretSource = File(
      'windows/runner/scope_secret_store.cpp',
    ).readAsStringSync();
    final collectionsHeader = scopeSecretSource.indexOf(
      '#include <winrt/Windows.Foundation.Collections.h>',
    );
    final jsonHeader = scopeSecretSource.indexOf(
      '#include <winrt/Windows.Data.Json.h>',
    );
    expect(collectionsHeader, greaterThanOrEqualTo(0));
    expect(jsonHeader, greaterThan(collectionsHeader));
  });

  test('Windows runner keeps the stable x64 product and window contract', () {
    final cmake = File('windows/CMakeLists.txt').readAsStringSync();
    final runnerCmake = File(
      'windows/runner/CMakeLists.txt',
    ).readAsStringSync();
    final main = File('windows/runner/main.cpp').readAsStringSync();
    final window = File('windows/runner/flutter_window.cpp').readAsStringSync();
    final manifest = File(
      'windows/runner/runner.exe.manifest',
    ).readAsStringSync();
    final resources = File('windows/runner/Runner.rc').readAsStringSync();

    expect(cmake, contains('set(BINARY_NAME "AWikiMe")'));
    expect(cmake, contains('AWiki Me for Windows supports x64 builds only'));
    expect(cmake, contains('NOT CMAKE_SIZEOF_VOID_P EQUAL 8'));
    expect(main, contains('Win32Window::Size size(1280, 800)'));
    expect(window, contains('::MulDiv(960, dpi, 96)'));
    expect(window, contains('::MulDiv(640, dpi, 96)'));
    expect(manifest, contains('>PerMonitorV2</dpiAwareness>'));
    expect(manifest, contains('>true</longPathAware>'));
    expect(
      manifest,
      contains('requestedExecutionLevel level="asInvoker" uiAccess="false"'),
    );
    expect(resources, contains('VALUE "CompanyName", "AWiki"'));
    expect(resources, contains('VALUE "ProductName", "AWiki Me"'));
    expect(resources, contains('VALUE "OriginalFilename", "AWikiMe.exe"'));
    expect(runnerCmake, contains('AWIKI_RELEASE_SCOPE=1'));
    expect(runnerCmake, contains('uuid.lib'));
    expect(runnerCmake, contains('windowsapp.lib'));
  });

  test('Windows shell uses one IPC and graceful-exit boundary', () {
    final constants = File('windows/runner/app_constants.h').readAsStringSync();
    final main = File('windows/runner/main.cpp').readAsStringSync();
    final shell = File('windows/runner/desktop_shell.cpp').readAsStringSync();

    expect(constants, contains(r'Local\\ai.awiki.awikime.single-instance'));
    expect(constants, contains('AWiki.AWikiMe'));
    expect(constants, contains('42f66431-9bea-46c4-ac14-475b9044a2be'));
    expect(main, contains('"--shutdown-for-update"'));
    expect(main, contains('::OpenProcess(SYNCHRONIZE'));
    expect(main, contains('WaitForSingleObject(primary_process, 30000)'));
    expect(main, isNot(contains('::ReleaseMutex(single_instance)')));
    expect(shell, contains('case WM_CLOSE:'));
    expect(shell, contains('HideWindow();'));
    expect(shell, contains('RequestExit("requestExit")'));
    expect(shell, contains('RequestExit("shutdownForUpdate")'));
    expect(shell, contains('method == "ready"'));
    expect(shell, contains('method == "completeExit"'));
    expect(shell, contains('if (!exit_requested_)'));
    expect(shell, contains('::PostMessageW(window_, awiki::kExitReadyMessage'));
    expect(shell, contains('SetMethodCallHandler(nullptr)'));
    expect(
      shell,
      isNot(contains('result->Success(\n                std::make_unique')),
    );
    expect(shell, contains('CLSID_TaskbarList'));
    expect(shell, contains('SetOverlayIcon'));
    expect(shell, contains('NOTIFYICON_VERSION_4'));
    expect(shell, contains('static_cast<UINT>(HIWORD(lparam))'));
    expect(shell, contains('!= tray_icon_.uID'));
    expect(shell, contains('CreateUnreadTrayIcon'));
    expect(shell, contains('BuildTrayTooltip'));
    expect(shell, contains('std::to_wstring(unread_count_)'));
    expect(shell, contains('Shell_NotifyIconW(NIM_MODIFY'));
    expect(shell, contains('case WM_DPICHANGED:'));
    expect(shell, contains('RebuildTrayIcon(HIWORD(wparam))'));
    expect(shell, contains('message == taskbar_created_message_'));
    expect(shell, contains('CreateUnreadOverlayIcon(unread_count_)'));
    expect(
      shell,
      contains(
        'unread_count_ > 0 ? CreateUnreadTrayIcon(dpi)\n'
        '                                        : LoadBaseTrayIcon(dpi)',
      ),
    );
    expect(
      shell.indexOf('HICON previous = tray_icon_.hIcon'),
      greaterThan(shell.indexOf('Shell_NotifyIconW(NIM_MODIFY')),
    );
    expect(
      shell.indexOf('::DestroyIcon(previous)'),
      greaterThan(shell.indexOf('HICON previous = tray_icon_.hIcon')),
    );
    expect(shell, contains('FOLDERID_LocalAppData'));
    expect(shell, contains('L"AWiki" / L"AWikiMe"'));
    expect(shell, isNot(contains('::DestroyWindow(window_)')));
    final window = File('windows/runner/flutter_window.cpp').readAsStringSync();
    expect(window, contains('message == awiki::kExitReadyMessage'));
    expect(window, contains('::DestroyWindow(hwnd)'));
  });

  test('Windows native title bar remains explicitly light', () {
    final window = File('windows/runner/win32_window.cpp').readAsStringSync();

    expect(window, contains('ApplyLightTitleBar(window)'));
    expect(window, contains('const BOOL enable_dark_mode = FALSE'));
    expect(window, contains('DWMWA_USE_IMMERSIVE_DARK_MODE'));
    expect(window, contains('DWMWA_CAPTION_COLOR'));
    expect(window, contains('DWMWA_TEXT_COLOR'));
    expect(window, contains('DWMWA_BORDER_COLOR'));
    expect(window, contains('kLightCaptionColor = RGB(250, 249, 254)'));
    expect(window, contains('kLightCaptionTextColor = RGB(26, 28, 28)'));
    expect(window, contains('kLightBorderColor = RGB(221, 229, 240)'));
    expect(window, contains('case WM_THEMECHANGED:'));
    expect(window, isNot(contains('AppsUseLightTheme')));
  });

  test('Windows region capture is native, asynchronous, and atomic', () {
    final constants = File('windows/runner/app_constants.h').readAsStringSync();
    final capture = File(
      'windows/runner/windows_region_capture.cpp',
    ).readAsStringSync();
    final window = File('windows/runner/flutter_window.cpp').readAsStringSync();
    final runnerCmake = File(
      'windows/runner/CMakeLists.txt',
    ).readAsStringSync();

    expect(constants, contains('ai.awiki.awikime/attachment_picker'));
    expect(capture, contains('call.method_name() == "cancelCapture"'));
    expect(capture, contains('call.method_name() != "captureRegion"'));
    expect(capture, contains('StringArgument(*arguments, "outputPath")'));
    expect(capture, contains('capture_invalid_path'));
    expect(capture, contains('capture_busy'));
    expect(capture, contains('capture_failed'));
    expect(capture, contains('kCaptureTimeoutMilliseconds = 120000'));
    expect(capture, contains('SM_XVIRTUALSCREEN'));
    expect(capture, contains('SM_YVIRTUALSCREEN'));
    expect(capture, contains('SRCCOPY | CAPTUREBLT'));
    expect(capture, contains('::EnumDisplayMonitors'));
    expect(capture, contains('WS_EX_TOPMOST | WS_EX_TOOLWINDOW'));
    expect(capture, contains('WM_RBUTTONDOWN'));
    expect(capture, contains('WM_CAPTURECHANGED'));
    expect(capture, contains('WM_CANCELMODE'));
    expect(capture, contains('LOWORD(wparam) == WA_INACTIVE'));
    expect(capture, contains('wparam == VK_ESCAPE'));
    expect(capture, contains('GUID_ContainerFormatPng'));
    expect(capture, contains('output_path_ + L".part"'));
    expect(capture, contains('MOVEFILE_REPLACE_EXISTING'));
    expect(capture, contains('MOVEFILE_WRITE_THROUGH'));
    expect(capture, isNot(contains('GetMessage')));
    expect(capture, isNot(contains('OpenClipboard')));
    expect(capture, isNot(contains('HideWindow')));
    expect(window, contains('std::make_unique<WindowsRegionCapture>'));
    expect(runnerCmake, contains('"windows_region_capture.cpp"'));
    expect(runnerCmake, contains('"windowscodecs.lib"'));
  });

  test('Windows scope secrets stay in Credential Manager with CAS mutexes', () {
    final source = File(
      'windows/runner/scope_secret_store.cpp',
    ).readAsStringSync();

    expect(source, contains('CRED_TYPE_GENERIC'));
    expect(source, contains('CRED_PERSIST_LOCAL_MACHINE'));
    expect(
      source,
      contains('credential->Persist == CRED_PERSIST_LOCAL_MACHINE'),
    );
    expect(source, contains('account == credential->UserName'));
    expect(source, contains('::CredReadW'));
    expect(source, contains('::CredWriteW'));
    expect(source, contains('::CredDeleteW'));
    expect(source, contains('Local\\\\AWikiMe.ScopeSecret.'));
    expect(source, contains('scope_secret_already_exists'));
    expect(source, contains('scope_secret_revision_conflict'));
    expect(source, contains('scope_secret_access_denied'));
    expect(source, contains('scope_secret_corrupt'));
    expect(source, contains('kMaxSafeJsonInteger'));
    expect(source, contains('::SecureZeroMemory(value.data(), value.size())'));
    expect(source, isNot(contains('writeAsString')));
  });
}
