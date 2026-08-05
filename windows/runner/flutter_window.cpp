#include "flutter_window.h"

#include <optional>

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include "app_constants.h"
#include "flutter/generated_plugin_registrant.h"
#include "window_placement.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  awiki::WindowPlacementStore::Restore(GetHandle());

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  desktop_shell_ = std::make_unique<DesktopShell>(
      GetHandle(), flutter_controller_->engine());
  windows_region_capture_ = std::make_unique<WindowsRegionCapture>(
      GetHandle(), flutter_controller_->engine());
  desktop_window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          awiki::kDesktopWindowChannel,
          &flutter::StandardMethodCodec::GetInstance());
  desktop_window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "resetPlacement") {
          awiki::WindowPlacementStore::Reset(GetHandle());
          result->Success();
          return;
        }
        result->NotImplemented();
      });
  desktop_startup_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          awiki::kDesktopStartupChannel,
          &flutter::StandardMethodCodec::GetInstance());
  desktop_startup_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "presentReadyContent") {
          PresentStartupContent();
          result->Success();
          return;
        }
        result->NotImplemented();
      });
  scope_secret_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          awiki::kScopeSecretChannel,
          &flutter::StandardMethodCodec::GetInstance());
  scope_secret_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        scope_secret_store_.HandleMethodCall(call, std::move(result));
      });

  if (::SetTimer(GetHandle(), awiki::kStartupPresentationTimerId, 12000,
                 nullptr) == 0) {
    PresentStartupContent();
  }

  // Keep rendering while hidden so Flutter can finish the real destination
  // frame and signal that the native window is ready to be presented.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  ::KillTimer(GetHandle(), awiki::kStartupPresentationTimerId);
  awiki::WindowPlacementStore::Save(GetHandle());
  if (desktop_startup_channel_ != nullptr) {
    desktop_startup_channel_->SetMethodCallHandler(nullptr);
  }
  desktop_startup_channel_.reset();
  if (desktop_window_channel_ != nullptr) {
    desktop_window_channel_->SetMethodCallHandler(nullptr);
  }
  desktop_window_channel_.reset();
  if (scope_secret_channel_ != nullptr) {
    scope_secret_channel_->SetMethodCallHandler(nullptr);
  }
  scope_secret_channel_.reset();
  windows_region_capture_.reset();
  desktop_shell_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::PresentStartupContent() {
  if (startup_content_presented_) {
    return;
  }
  startup_content_presented_ = true;
  ::KillTimer(GetHandle(), awiki::kStartupPresentationTimerId);
  Show();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd,
                              UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Destroying the window synchronously from DesktopShell would destroy that
  // object before its message handler returns. Keep final destruction at the
  // owning FlutterWindow boundary instead.
  if (message == awiki::kExitReadyMessage) {
    ::DestroyWindow(hwnd);
    return 0;
  }

  if (message == WM_TIMER &&
      wparam == awiki::kStartupPresentationTimerId) {
    PresentStartupContent();
    return 0;
  }

  if (message == WM_EXITSIZEMOVE ||
      (message == WM_SIZE && wparam == SIZE_MAXIMIZED)) {
    awiki::WindowPlacementStore::Save(hwnd);
  }

  if (desktop_shell_) {
    const std::optional<LRESULT> shell_result =
        desktop_shell_->HandleWindowMessage(message, wparam, lparam);
    if (shell_result.has_value()) {
      return *shell_result;
    }
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      if (flutter_controller_) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
    case WM_GETMINMAXINFO: {
      auto* min_max = reinterpret_cast<MINMAXINFO*>(lparam);
      const UINT dpi = ::GetDpiForWindow(hwnd);
      const SIZE minimum =
          awiki::WindowPlacementStore::MinimumTrackSize(hwnd, dpi);
      min_max->ptMinTrackSize.x = minimum.cx;
      min_max->ptMinTrackSize.y = minimum.cy;
      return 0;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
