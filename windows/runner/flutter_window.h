#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "desktop_shell.h"
#include "scope_secret_store.h"
#include "win32_window.h"
#include "windows_region_capture.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window,
                         UINT const message,
                         WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<DesktopShell> desktop_shell_;
  std::unique_ptr<WindowsRegionCapture> windows_region_capture_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      scope_secret_channel_;
  ScopeSecretStore scope_secret_store_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
