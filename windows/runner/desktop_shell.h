#ifndef RUNNER_DESKTOP_SHELL_H_
#define RUNNER_DESKTOP_SHELL_H_

#include <windows.h>
#include <shellapi.h>
#include <shobjidl.h>

#include <flutter/encodable_value.h>
#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>

#include <memory>
#include <optional>
#include <string>

class DesktopShell {
 public:
  DesktopShell(HWND window, flutter::FlutterEngine* engine);
  ~DesktopShell();

  DesktopShell(const DesktopShell&) = delete;
  DesktopShell& operator=(const DesktopShell&) = delete;

  std::optional<LRESULT> HandleWindowMessage(UINT message,
                                             WPARAM wparam,
                                             LPARAM lparam);
  void ActivateWindow();
  void HideWindow();

 private:
  void RegisterMethodChannel(flutter::FlutterEngine* engine);
  void InitializeTaskbar();
  void CreateTrayIcon();
  void RemoveTrayIcon();
  void ShowTrayMenu();
  void RequestExit(const char* event_type);
  void SendShellEvent(const char* event_type);
  void UpdateUnreadCount(int count);
  void ApplyTaskbarOverlay();
  HICON CreateUnreadOverlayIcon(int count) const;
  flutter::EncodableMap GetStorageRoots() const;

  HWND window_ = nullptr;
  NOTIFYICONDATAW tray_icon_{};
  bool tray_icon_added_ = false;
  bool tray_icon_uses_version_4_ = false;
  bool dart_ready_ = false;
  bool exit_requested_ = false;
  bool exit_completed_ = false;
  std::string pending_exit_type_;
  int unread_count_ = 0;
  UINT activate_message_ = 0;
  UINT shutdown_for_update_message_ = 0;
  UINT taskbar_created_message_ = 0;
  UINT taskbar_button_created_message_ = 0;
  ITaskbarList3* taskbar_ = nullptr;
  HICON overlay_icon_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_DESKTOP_SHELL_H_
