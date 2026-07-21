#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shellapi.h>
#include <shobjidl.h>

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <string>
#include <thread>
#include <vector>

#include "app_constants.h"
#include "flutter_window.h"
#include "utils.h"

namespace {

bool HasArgument(const std::vector<std::string>& arguments,
                 const char* expected) {
  return std::find(arguments.begin(), arguments.end(), expected) !=
         arguments.end();
}

HWND FindPrimaryWindow() {
  for (int attempt = 0; attempt < 50; ++attempt) {
    HWND window = ::FindWindowW(awiki::kWindowClassName, nullptr);
    if (window != nullptr) {
      return window;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
  }
  return nullptr;
}

bool NotifyPrimaryWindow(UINT message, HANDLE* primary_process) {
  *primary_process = nullptr;
  HWND window = FindPrimaryWindow();
  if (window == nullptr || message == 0) {
    return false;
  }
  DWORD primary_process_id = 0;
  ::GetWindowThreadProcessId(window, &primary_process_id);
  if (primary_process_id != 0) {
    *primary_process = ::OpenProcess(SYNCHRONIZE, FALSE, primary_process_id);
    // A user-launched second process normally owns foreground activation
    // rights. Transfer them before asking the existing process to show itself.
    ::AllowSetForegroundWindow(primary_process_id);
  }
  DWORD_PTR ignored = 0;
  return ::SendMessageTimeoutW(window, message, awiki::kIpcMessageCookie, 0,
                               SMTO_ABORTIFHUNG | SMTO_BLOCK, 5000,
                               &ignored) != 0;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance,
                      _In_opt_ HINSTANCE prev,
                      _In_ wchar_t* command_line,
                      _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  const HRESULT com_status =
      ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  if (FAILED(com_status)) {
    return EXIT_FAILURE;
  }

  std::vector<std::string> command_line_arguments = GetCommandLineArguments();
  const bool shutdown_for_update =
      HasArgument(command_line_arguments, "--shutdown-for-update");

  HANDLE single_instance =
      ::CreateMutexW(nullptr, TRUE, awiki::kSingleInstanceMutexName);
  if (single_instance == nullptr) {
    ::CoUninitialize();
    return EXIT_FAILURE;
  }
  const bool instance_already_running =
      ::GetLastError() == ERROR_ALREADY_EXISTS;
  if (instance_already_running) {
    const UINT message = ::RegisterWindowMessageW(
        shutdown_for_update ? awiki::kShutdownForUpdateMessageName
                            : awiki::kActivateMessageName);
    HANDLE primary_process = nullptr;
    const bool delivered = NotifyPrimaryWindow(message, &primary_process);
    if (!shutdown_for_update) {
      if (primary_process != nullptr) {
        ::CloseHandle(primary_process);
      }
      ::CloseHandle(single_instance);
      ::CoUninitialize();
      return delivered ? EXIT_SUCCESS : EXIT_FAILURE;
    }
    if (primary_process == nullptr) {
      ::CloseHandle(single_instance);
      ::CoUninitialize();
      return EXIT_FAILURE;
    }
    const DWORD wait = ::WaitForSingleObject(primary_process, 30000);
    ::CloseHandle(primary_process);
    ::CloseHandle(single_instance);
    ::CoUninitialize();
    // A process handle is signaled only after the primary process has fully
    // terminated, so its loaded DLLs can now be replaced safely. It is safe to
    // continue if it exited independently while IPC was being delivered.
    return wait == WAIT_OBJECT_0 ? EXIT_SUCCESS : EXIT_FAILURE;
  }

  if (shutdown_for_update) {
    ::CoUninitialize();
    // Keep the primary-instance mutex owned until process termination.
    return EXIT_SUCCESS;
  }

  if (FAILED(
          ::SetCurrentProcessExplicitAppUserModelID(awiki::kAppUserModelId))) {
    ::CoUninitialize();
    return EXIT_FAILURE;
  }

  flutter::DartProject project(L"data");

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 800);
  if (!window.Create(awiki::kWindowTitle, origin, size)) {
    window.Destroy();
    ::CoUninitialize();
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  int process_exit_code = EXIT_SUCCESS;
  ::MSG msg{};
  BOOL message_status = FALSE;
  while ((message_status = ::GetMessage(&msg, nullptr, 0, 0)) > 0) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }
  if (message_status == -1) {
    process_exit_code = EXIT_FAILURE;
  }

  window.Destroy();
  ::CoUninitialize();
  // The process owns the mutex for its entire lifetime. Let process teardown
  // close it so a second primary cannot start while native teardown is active.
  return process_exit_code;
}
