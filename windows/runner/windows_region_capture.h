#ifndef RUNNER_WINDOWS_REGION_CAPTURE_H_
#define RUNNER_WINDOWS_REGION_CAPTURE_H_

#include <windows.h>

#include <flutter/encodable_value.h>
#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/method_result.h>

#include <memory>
#include <optional>
#include <string>
#include <vector>

// Owns the Windows implementation of the attachment picker's interactive
// region capture. Selection runs on the runner's normal message loop, so Dart
// remains asynchronous without introducing a nested native message pump.
class WindowsRegionCapture {
 public:
  WindowsRegionCapture(HWND owner, flutter::FlutterEngine* engine);
  ~WindowsRegionCapture();

  WindowsRegionCapture(const WindowsRegionCapture&) = delete;
  WindowsRegionCapture& operator=(const WindowsRegionCapture&) = delete;

 private:
  struct Overlay {
    HWND window = nullptr;
    RECT bounds{};
    HBITMAP dimmed_snapshot = nullptr;
  };

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  bool StartCapture(const std::wstring& output_path, std::string* error);
  bool CaptureVirtualDesktop(std::string* error);
  bool CreateSelectionOverlays(std::string* error);
  HBITMAP CreateDimmedSnapshot(const RECT& bounds) const;
  void UpdatePointer(POINT point);
  void InvalidateOverlays() const;
  void PaintOverlay(HWND window) const;
  void CompleteCapture(bool save_selection);
  bool SaveSelection(std::string* error) const;
  void ReleaseCaptureResources();
  std::optional<RECT> SelectionRectangle() const;
  Overlay* FindOverlay(HWND window);
  const Overlay* FindOverlay(HWND window) const;

  static BOOL CALLBACK CollectMonitor(HMONITOR monitor,
                                      HDC device_context,
                                      RECT* bounds,
                                      LPARAM context);
  static LRESULT CALLBACK OverlayWindowProc(HWND window,
                                            UINT message,
                                            WPARAM wparam,
                                            LPARAM lparam);
  LRESULT HandleOverlayMessage(HWND window,
                               UINT message,
                               WPARAM wparam,
                               LPARAM lparam);

  HWND owner_ = nullptr;
  HINSTANCE instance_ = nullptr;
  bool class_registered_ = false;
  bool selecting_ = false;
  bool completing_ = false;
  POINT selection_start_{};
  POINT selection_end_{};
  RECT virtual_bounds_{};
  HBITMAP desktop_snapshot_ = nullptr;
  HWND pointer_capture_window_ = nullptr;
  HWND timer_window_ = nullptr;
  std::wstring output_path_;
  std::vector<RECT> monitor_bounds_;
  std::vector<Overlay> overlays_;
  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
      pending_result_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_WINDOWS_REGION_CAPTURE_H_
