#include "windows_region_capture.h"

#include <windows.h>
#include <windowsx.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <sstream>
#include <string>
#include <utility>

#include "app_constants.h"

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;

constexpr wchar_t kOverlayWindowClass[] =
    L"AWikiMe.WindowsRegionCaptureOverlay";
constexpr UINT_PTR kCaptureTimerId = 1;
constexpr UINT kCaptureTimeoutMilliseconds = 120000;

int RectWidth(const RECT& rectangle) {
  return rectangle.right - rectangle.left;
}

int RectHeight(const RECT& rectangle) {
  return rectangle.bottom - rectangle.top;
}

std::string Win32Failure(const char* operation, DWORD error) {
  std::ostringstream message;
  message << operation << " failed with Win32 error " << error;
  return message.str();
}

std::string HResultFailure(const char* operation, HRESULT result) {
  std::ostringstream message;
  message << operation << " failed with HRESULT 0x" << std::hex
          << static_cast<uint32_t>(result);
  return message.str();
}

std::optional<std::wstring> Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return std::nullopt;
  }
  const int length = ::MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
      static_cast<int>(value.size()), nullptr, 0);
  if (length <= 0) {
    return std::nullopt;
  }
  std::wstring converted(static_cast<size_t>(length), L'\0');
  if (::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                            static_cast<int>(value.size()), converted.data(),
                            length) != length) {
    return std::nullopt;
  }
  return converted;
}

const EncodableMap* ArgumentsMap(const EncodableValue* arguments) {
  return arguments == nullptr ? nullptr : std::get_if<EncodableMap>(arguments);
}

std::optional<std::string> StringArgument(const EncodableMap& arguments,
                                          const char* key) {
  const auto iterator =
      arguments.find(EncodableValue(std::string(key)));
  if (iterator == arguments.end()) {
    return std::nullopt;
  }
  const auto* value = std::get_if<std::string>(&iterator->second);
  if (value == nullptr || value->empty()) {
    return std::nullopt;
  }
  return *value;
}

bool EncodePngPart(HBITMAP snapshot,
                   const RECT& virtual_bounds,
                   const RECT& selection,
                   const std::wstring& part_path,
                   std::string* error) {
  ComPtr<IWICImagingFactory> factory;
  HRESULT result = ::CoCreateInstance(
      CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
      IID_PPV_ARGS(factory.GetAddressOf()));
  if (FAILED(result)) {
    *error = HResultFailure("CoCreateInstance(IWICImagingFactory)", result);
    return false;
  }

  ComPtr<IWICBitmap> source;
  result = factory->CreateBitmapFromHBITMAP(snapshot, nullptr,
                                            WICBitmapIgnoreAlpha,
                                            source.GetAddressOf());
  if (FAILED(result)) {
    *error = HResultFailure("CreateBitmapFromHBITMAP", result);
    return false;
  }

  WICRect clip_bounds{
      selection.left - virtual_bounds.left,
      selection.top - virtual_bounds.top,
      RectWidth(selection),
      RectHeight(selection),
  };
  ComPtr<IWICBitmapClipper> clipper;
  result = factory->CreateBitmapClipper(clipper.GetAddressOf());
  if (SUCCEEDED(result)) {
    result = clipper->Initialize(source.Get(), &clip_bounds);
  }
  if (FAILED(result)) {
    *error = HResultFailure("IWICBitmapClipper::Initialize", result);
    return false;
  }

  ComPtr<IWICStream> stream;
  result = factory->CreateStream(stream.GetAddressOf());
  if (SUCCEEDED(result)) {
    result = stream->InitializeFromFilename(part_path.c_str(), GENERIC_WRITE);
  }
  if (FAILED(result)) {
    *error = HResultFailure("IWICStream::InitializeFromFilename", result);
    return false;
  }

  ComPtr<IWICBitmapEncoder> encoder;
  result = factory->CreateEncoder(GUID_ContainerFormatPng, nullptr,
                                  encoder.GetAddressOf());
  if (SUCCEEDED(result)) {
    result = encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache);
  }
  if (FAILED(result)) {
    *error = HResultFailure("IWICBitmapEncoder::Initialize", result);
    return false;
  }

  ComPtr<IWICBitmapFrameEncode> frame;
  ComPtr<IPropertyBag2> properties;
  result = encoder->CreateNewFrame(frame.GetAddressOf(),
                                   properties.GetAddressOf());
  if (SUCCEEDED(result)) {
    result = frame->Initialize(properties.Get());
  }
  if (SUCCEEDED(result)) {
    result = frame->SetSize(static_cast<UINT>(RectWidth(selection)),
                            static_cast<UINT>(RectHeight(selection)));
  }
  WICPixelFormatGUID pixel_format = GUID_WICPixelFormat24bppBGR;
  if (SUCCEEDED(result)) {
    result = frame->SetPixelFormat(&pixel_format);
  }
  if (SUCCEEDED(result)) {
    result = frame->WriteSource(clipper.Get(), nullptr);
  }
  if (SUCCEEDED(result)) {
    result = frame->Commit();
  }
  if (SUCCEEDED(result)) {
    result = encoder->Commit();
  }
  if (FAILED(result)) {
    *error = HResultFailure("WIC PNG encoding", result);
    return false;
  }
  return true;
}

}  // namespace

WindowsRegionCapture::WindowsRegionCapture(HWND owner,
                                           flutter::FlutterEngine* engine)
    : owner_(owner), instance_(::GetModuleHandleW(nullptr)) {
  channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          engine->messenger(), awiki::kAttachmentPickerChannel,
          &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        HandleMethodCall(call, std::move(result));
      });
}

WindowsRegionCapture::~WindowsRegionCapture() {
  if (channel_ != nullptr) {
    channel_->SetMethodCallHandler(nullptr);
  }
  pending_result_.reset();
  ReleaseCaptureResources();
  if (class_registered_) {
    ::UnregisterClassW(kOverlayWindowClass, instance_);
  }
}

void WindowsRegionCapture::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "cancelCapture") {
    const bool was_active = pending_result_ != nullptr;
    if (was_active) {
      CompleteCapture(false);
    }
    result->Success(EncodableValue(was_active));
    return;
  }
  if (call.method_name() != "captureRegion") {
    result->NotImplemented();
    return;
  }
  if (pending_result_ != nullptr) {
    result->Error("capture_busy",
                  "A Windows region capture is already active.");
    return;
  }

  const EncodableMap* arguments = ArgumentsMap(call.arguments());
  const std::optional<std::string> output_path =
      arguments == nullptr ? std::nullopt
                           : StringArgument(*arguments, "outputPath");
  const std::optional<std::wstring> wide_output_path =
      output_path.has_value() ? Utf8ToWide(*output_path) : std::nullopt;
  if (!wide_output_path.has_value() ||
      wide_output_path->find(L'\0') != std::wstring::npos ||
      !std::filesystem::path(*wide_output_path).is_absolute()) {
    result->Error("capture_invalid_path",
                  "captureRegion requires a valid UTF-8 outputPath.");
    return;
  }

  pending_result_ = std::move(result);
  std::string error;
  if (!StartCapture(*wide_output_path, &error)) {
    auto failed_result = std::move(pending_result_);
    ReleaseCaptureResources();
    failed_result->Error("capture_failed", error);
  }
}

bool WindowsRegionCapture::StartCapture(const std::wstring& output_path,
                                        std::string* error) {
  output_path_ = output_path;

  if (!CaptureVirtualDesktop(error)) {
    return false;
  }

  monitor_bounds_.clear();
  if (!::EnumDisplayMonitors(nullptr, nullptr, CollectMonitor,
                             reinterpret_cast<LPARAM>(this)) ||
      monitor_bounds_.empty()) {
    monitor_bounds_.push_back(virtual_bounds_);
  }

  if (!CreateSelectionOverlays(error)) {
    return false;
  }
  return true;
}

bool WindowsRegionCapture::CaptureVirtualDesktop(std::string* error) {
  // The runner is PerMonitorV2-aware, so these are physical pixel coordinates
  // across the whole desktop, including monitors with negative origins.
  virtual_bounds_.left = ::GetSystemMetrics(SM_XVIRTUALSCREEN);
  virtual_bounds_.top = ::GetSystemMetrics(SM_YVIRTUALSCREEN);
  virtual_bounds_.right =
      virtual_bounds_.left + ::GetSystemMetrics(SM_CXVIRTUALSCREEN);
  virtual_bounds_.bottom =
      virtual_bounds_.top + ::GetSystemMetrics(SM_CYVIRTUALSCREEN);
  if (RectWidth(virtual_bounds_) <= 0 || RectHeight(virtual_bounds_) <= 0) {
    *error = "The Windows virtual desktop has invalid bounds.";
    return false;
  }

  HDC screen_context = ::GetDC(nullptr);
  if (screen_context == nullptr) {
    *error = Win32Failure("GetDC", ::GetLastError());
    return false;
  }
  HDC snapshot_context = ::CreateCompatibleDC(screen_context);
  if (snapshot_context == nullptr) {
    const DWORD last_error = ::GetLastError();
    ::ReleaseDC(nullptr, screen_context);
    *error = Win32Failure("CreateCompatibleDC", last_error);
    return false;
  }
  desktop_snapshot_ =
      ::CreateCompatibleBitmap(screen_context, RectWidth(virtual_bounds_),
                               RectHeight(virtual_bounds_));
  if (desktop_snapshot_ == nullptr) {
    const DWORD last_error = ::GetLastError();
    ::DeleteDC(snapshot_context);
    ::ReleaseDC(nullptr, screen_context);
    *error = Win32Failure("CreateCompatibleBitmap", last_error);
    return false;
  }

  HGDIOBJ previous_bitmap =
      ::SelectObject(snapshot_context, desktop_snapshot_);
  const BOOL copied = ::BitBlt(
      snapshot_context, 0, 0, RectWidth(virtual_bounds_),
      RectHeight(virtual_bounds_), screen_context, virtual_bounds_.left,
      virtual_bounds_.top, SRCCOPY | CAPTUREBLT);
  ::SelectObject(snapshot_context, previous_bitmap);
  ::DeleteDC(snapshot_context);
  ::ReleaseDC(nullptr, screen_context);
  if (!copied) {
    const DWORD last_error = ::GetLastError();
    ::DeleteObject(desktop_snapshot_);
    desktop_snapshot_ = nullptr;
    *error = Win32Failure("BitBlt", last_error);
    return false;
  }
  return true;
}

bool WindowsRegionCapture::CreateSelectionOverlays(std::string* error) {
  WNDCLASSEXW window_class{};
  window_class.cbSize = sizeof(window_class);
  window_class.style = CS_HREDRAW | CS_VREDRAW;
  window_class.lpfnWndProc = OverlayWindowProc;
  window_class.hInstance = instance_;
  window_class.hCursor = ::LoadCursorW(nullptr, IDC_CROSS);
  window_class.lpszClassName = kOverlayWindowClass;
  if (::RegisterClassExW(&window_class) != 0) {
    class_registered_ = true;
  } else if (::GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
    *error = Win32Failure("RegisterClassExW", ::GetLastError());
    return false;
  }

  overlays_.reserve(monitor_bounds_.size());
  for (const RECT& bounds : monitor_bounds_) {
    HBITMAP dimmed_snapshot = CreateDimmedSnapshot(bounds);
    if (dimmed_snapshot == nullptr) {
      *error = Win32Failure("CreateDIBSection", ::GetLastError());
      return false;
    }
    HWND overlay = ::CreateWindowExW(
        WS_EX_TOPMOST | WS_EX_TOOLWINDOW, kOverlayWindowClass, L"", WS_POPUP,
        bounds.left, bounds.top, RectWidth(bounds), RectHeight(bounds), owner_,
        nullptr, instance_, this);
    if (overlay == nullptr) {
      const DWORD last_error = ::GetLastError();
      ::DeleteObject(dimmed_snapshot);
      *error = Win32Failure("CreateWindowExW", last_error);
      return false;
    }
    overlays_.push_back(Overlay{overlay, bounds, dimmed_snapshot});
  }

  for (const Overlay& overlay : overlays_) {
    ::SetWindowPos(overlay.window, HWND_TOPMOST, overlay.bounds.left,
                   overlay.bounds.top, RectWidth(overlay.bounds),
                   RectHeight(overlay.bounds),
                   SWP_NOOWNERZORDER | SWP_SHOWWINDOW | SWP_NOACTIVATE);
  }
  timer_window_ = overlays_.front().window;
  if (::SetTimer(timer_window_, kCaptureTimerId,
                 kCaptureTimeoutMilliseconds, nullptr) == 0) {
    *error = Win32Failure("SetTimer", ::GetLastError());
    return false;
  }
  ::SetForegroundWindow(timer_window_);
  ::SetFocus(timer_window_);
  return true;
}

HBITMAP WindowsRegionCapture::CreateDimmedSnapshot(const RECT& bounds) const {
  const int width = RectWidth(bounds);
  const int height = RectHeight(bounds);
  if (width <= 0 || height <= 0) {
    return nullptr;
  }

  BITMAPINFO bitmap_info{};
  bitmap_info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bitmap_info.bmiHeader.biWidth = width;
  bitmap_info.bmiHeader.biHeight = -height;
  bitmap_info.bmiHeader.biPlanes = 1;
  bitmap_info.bmiHeader.biBitCount = 32;
  bitmap_info.bmiHeader.biCompression = BI_RGB;

  HDC screen_context = ::GetDC(nullptr);
  if (screen_context == nullptr) {
    return nullptr;
  }
  void* pixel_data = nullptr;
  HBITMAP dimmed = ::CreateDIBSection(screen_context, &bitmap_info,
                                      DIB_RGB_COLORS, &pixel_data, nullptr, 0);
  if (dimmed == nullptr || pixel_data == nullptr) {
    if (dimmed != nullptr) {
      ::DeleteObject(dimmed);
    }
    ::ReleaseDC(nullptr, screen_context);
    return nullptr;
  }

  HDC destination_context = ::CreateCompatibleDC(screen_context);
  HDC source_context = ::CreateCompatibleDC(screen_context);
  if (destination_context == nullptr || source_context == nullptr) {
    if (destination_context != nullptr) {
      ::DeleteDC(destination_context);
    }
    if (source_context != nullptr) {
      ::DeleteDC(source_context);
    }
    ::DeleteObject(dimmed);
    ::ReleaseDC(nullptr, screen_context);
    return nullptr;
  }
  HGDIOBJ previous_destination =
      ::SelectObject(destination_context, dimmed);
  HGDIOBJ previous_source =
      ::SelectObject(source_context, desktop_snapshot_);
  const BOOL copied = ::BitBlt(
      destination_context, 0, 0, width, height, source_context,
      bounds.left - virtual_bounds_.left,
      bounds.top - virtual_bounds_.top, SRCCOPY);
  ::SelectObject(destination_context, previous_destination);
  ::SelectObject(source_context, previous_source);
  ::DeleteDC(destination_context);
  ::DeleteDC(source_context);
  ::ReleaseDC(nullptr, screen_context);
  if (!copied) {
    ::DeleteObject(dimmed);
    return nullptr;
  }

  auto* pixels = static_cast<uint8_t*>(pixel_data);
  const size_t pixel_count =
      static_cast<size_t>(width) * static_cast<size_t>(height);
  for (size_t pixel = 0; pixel < pixel_count; ++pixel) {
    const size_t offset = pixel * 4;
    pixels[offset] = static_cast<uint8_t>(pixels[offset] * 3 / 5);
    pixels[offset + 1] = static_cast<uint8_t>(pixels[offset + 1] * 3 / 5);
    pixels[offset + 2] = static_cast<uint8_t>(pixels[offset + 2] * 3 / 5);
  }
  return dimmed;
}

void WindowsRegionCapture::UpdatePointer(POINT point) {
  point.x = std::clamp(point.x, virtual_bounds_.left, virtual_bounds_.right);
  point.y = std::clamp(point.y, virtual_bounds_.top, virtual_bounds_.bottom);
  selection_end_ = point;
  InvalidateOverlays();
}

void WindowsRegionCapture::InvalidateOverlays() const {
  for (const Overlay& overlay : overlays_) {
    ::InvalidateRect(overlay.window, nullptr, FALSE);
  }
}

void WindowsRegionCapture::PaintOverlay(HWND window) const {
  PAINTSTRUCT paint{};
  HDC paint_context = ::BeginPaint(window, &paint);
  if (paint_context == nullptr) {
    return;
  }
  const Overlay* overlay = FindOverlay(window);
  if (overlay == nullptr) {
    ::EndPaint(window, &paint);
    return;
  }

  HDC dimmed_context = ::CreateCompatibleDC(paint_context);
  if (dimmed_context != nullptr) {
    HGDIOBJ previous =
        ::SelectObject(dimmed_context, overlay->dimmed_snapshot);
    ::BitBlt(paint_context, 0, 0, RectWidth(overlay->bounds),
             RectHeight(overlay->bounds), dimmed_context, 0, 0, SRCCOPY);
    ::SelectObject(dimmed_context, previous);
    ::DeleteDC(dimmed_context);
  }

  const std::optional<RECT> selection = SelectionRectangle();
  if (selection.has_value()) {
    RECT visible_selection{};
    if (::IntersectRect(&visible_selection, &*selection, &overlay->bounds)) {
      HDC snapshot_context = ::CreateCompatibleDC(paint_context);
      if (snapshot_context != nullptr) {
        HGDIOBJ previous =
            ::SelectObject(snapshot_context, desktop_snapshot_);
        ::BitBlt(
            paint_context, visible_selection.left - overlay->bounds.left,
            visible_selection.top - overlay->bounds.top,
            RectWidth(visible_selection), RectHeight(visible_selection),
            snapshot_context,
            visible_selection.left - virtual_bounds_.left,
            visible_selection.top - virtual_bounds_.top, SRCCOPY);
        ::SelectObject(snapshot_context, previous);
        ::DeleteDC(snapshot_context);
      }
    }

    HPEN border = ::CreatePen(PS_SOLID, 2, RGB(31, 167, 118));
    if (border != nullptr) {
      HGDIOBJ previous_pen = ::SelectObject(paint_context, border);
      HGDIOBJ previous_brush =
          ::SelectObject(paint_context, ::GetStockObject(NULL_BRUSH));
      ::Rectangle(paint_context,
                  selection->left - overlay->bounds.left,
                  selection->top - overlay->bounds.top,
                  selection->right - overlay->bounds.left,
                  selection->bottom - overlay->bounds.top);
      ::SelectObject(paint_context, previous_brush);
      ::SelectObject(paint_context, previous_pen);
      ::DeleteObject(border);
    }
  }
  ::EndPaint(window, &paint);
}

void WindowsRegionCapture::CompleteCapture(bool save_selection) {
  if (pending_result_ == nullptr || completing_) {
    return;
  }
  completing_ = true;

  bool succeeded = false;
  bool write_failed = false;
  std::string error;
  if (save_selection && SelectionRectangle().has_value()) {
    succeeded = SaveSelection(&error);
    write_failed = !succeeded;
  }

  auto result = std::move(pending_result_);
  ReleaseCaptureResources();
  completing_ = false;
  if (write_failed) {
    result->Error("capture_failed", error);
  } else {
    result->Success(EncodableValue(succeeded));
  }
}

bool WindowsRegionCapture::SaveSelection(std::string* error) const {
  const std::optional<RECT> selection = SelectionRectangle();
  if (!selection.has_value()) {
    return false;
  }

  const std::wstring part_path = output_path_ + L".part";
  ::DeleteFileW(part_path.c_str());
  if (!EncodePngPart(desktop_snapshot_, virtual_bounds_, *selection,
                     part_path, error)) {
    ::DeleteFileW(part_path.c_str());
    return false;
  }
  if (!::MoveFileExW(part_path.c_str(), output_path_.c_str(),
                     MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
    const DWORD last_error = ::GetLastError();
    ::DeleteFileW(part_path.c_str());
    *error = Win32Failure("MoveFileExW", last_error);
    return false;
  }
  return true;
}

void WindowsRegionCapture::ReleaseCaptureResources() {
  if (timer_window_ != nullptr) {
    ::KillTimer(timer_window_, kCaptureTimerId);
    timer_window_ = nullptr;
  }
  if (pointer_capture_window_ != nullptr &&
      ::GetCapture() == pointer_capture_window_) {
    ::ReleaseCapture();
  }
  pointer_capture_window_ = nullptr;
  selecting_ = false;

  std::vector<Overlay> overlays = std::move(overlays_);
  overlays_.clear();
  for (const Overlay& overlay : overlays) {
    if (overlay.window != nullptr && ::IsWindow(overlay.window)) {
      ::DestroyWindow(overlay.window);
    }
    if (overlay.dimmed_snapshot != nullptr) {
      ::DeleteObject(overlay.dimmed_snapshot);
    }
  }
  monitor_bounds_.clear();
  if (desktop_snapshot_ != nullptr) {
    ::DeleteObject(desktop_snapshot_);
    desktop_snapshot_ = nullptr;
  }
  output_path_.clear();
}

std::optional<RECT> WindowsRegionCapture::SelectionRectangle() const {
  if (!selecting_) {
    return std::nullopt;
  }
  RECT selection{
      std::min(selection_start_.x, selection_end_.x),
      std::min(selection_start_.y, selection_end_.y),
      std::max(selection_start_.x, selection_end_.x),
      std::max(selection_start_.y, selection_end_.y),
  };
  if (RectWidth(selection) <= 0 || RectHeight(selection) <= 0) {
    return std::nullopt;
  }
  return selection;
}

WindowsRegionCapture::Overlay* WindowsRegionCapture::FindOverlay(HWND window) {
  const auto match =
      std::find_if(overlays_.begin(), overlays_.end(),
                   [window](const Overlay& overlay) {
                     return overlay.window == window;
                   });
  return match == overlays_.end() ? nullptr : &*match;
}

const WindowsRegionCapture::Overlay* WindowsRegionCapture::FindOverlay(
    HWND window) const {
  const auto match =
      std::find_if(overlays_.begin(), overlays_.end(),
                   [window](const Overlay& overlay) {
                     return overlay.window == window;
                   });
  return match == overlays_.end() ? nullptr : &*match;
}

BOOL CALLBACK WindowsRegionCapture::CollectMonitor(HMONITOR monitor,
                                                    HDC device_context,
                                                    RECT* bounds,
                                                    LPARAM context) {
  auto* capture = reinterpret_cast<WindowsRegionCapture*>(context);
  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(monitor_info);
  if (::GetMonitorInfoW(monitor, &monitor_info)) {
    capture->monitor_bounds_.push_back(monitor_info.rcMonitor);
  } else if (bounds != nullptr) {
    capture->monitor_bounds_.push_back(*bounds);
  }
  return TRUE;
}

LRESULT CALLBACK WindowsRegionCapture::OverlayWindowProc(HWND window,
                                                         UINT message,
                                                         WPARAM wparam,
                                                         LPARAM lparam) {
  WindowsRegionCapture* capture = nullptr;
  if (message == WM_NCCREATE) {
    const auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    capture = static_cast<WindowsRegionCapture*>(create->lpCreateParams);
    ::SetWindowLongPtrW(window, GWLP_USERDATA,
                        reinterpret_cast<LONG_PTR>(capture));
  } else {
    capture = reinterpret_cast<WindowsRegionCapture*>(
        ::GetWindowLongPtrW(window, GWLP_USERDATA));
  }
  if (capture != nullptr) {
    return capture->HandleOverlayMessage(window, message, wparam, lparam);
  }
  return ::DefWindowProcW(window, message, wparam, lparam);
}

LRESULT WindowsRegionCapture::HandleOverlayMessage(HWND window,
                                                   UINT message,
                                                   WPARAM wparam,
                                                   LPARAM lparam) {
  switch (message) {
    case WM_ERASEBKGND:
      return 1;
    case WM_PAINT:
      PaintOverlay(window);
      return 0;
    case WM_SETCURSOR:
      ::SetCursor(::LoadCursorW(nullptr, IDC_CROSS));
      return TRUE;
    case WM_LBUTTONDOWN: {
      POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      ::ClientToScreen(window, &point);
      selection_start_ = point;
      selection_end_ = point;
      selecting_ = true;
      pointer_capture_window_ = window;
      ::SetForegroundWindow(window);
      // Mouse capture keeps this overlay receiving moves and the button-up
      // while the selection crosses into another monitor's overlay.
      ::SetCapture(window);
      InvalidateOverlays();
      return 0;
    }
    case WM_MOUSEMOVE:
      if (selecting_) {
        POINT point{};
        if (::GetCursorPos(&point)) {
          UpdatePointer(point);
        }
      }
      return 0;
    case WM_LBUTTONUP:
      if (selecting_) {
        POINT point{};
        if (::GetCursorPos(&point)) {
          UpdatePointer(point);
        }
        CompleteCapture(true);
      }
      return 0;
    case WM_RBUTTONDOWN:
      CompleteCapture(false);
      return 0;
    case WM_CAPTURECHANGED:
      if (selecting_ &&
          reinterpret_cast<HWND>(lparam) != pointer_capture_window_) {
        CompleteCapture(false);
      }
      return 0;
    case WM_CANCELMODE:
      CompleteCapture(false);
      return 0;
    case WM_ACTIVATE:
      if (LOWORD(wparam) == WA_INACTIVE) {
        const HWND activated = reinterpret_cast<HWND>(lparam);
        if (activated == nullptr || FindOverlay(activated) == nullptr) {
          CompleteCapture(false);
          return 0;
        }
      }
      break;
    case WM_KEYDOWN:
    case WM_SYSKEYDOWN:
      if (wparam == VK_ESCAPE) {
        CompleteCapture(false);
        return 0;
      }
      break;
    case WM_TIMER:
      if (wparam == kCaptureTimerId) {
        CompleteCapture(false);
        return 0;
      }
      break;
    case WM_DISPLAYCHANGE:
    case WM_CLOSE:
      CompleteCapture(false);
      return 0;
    case WM_NCDESTROY:
      ::SetWindowLongPtrW(window, GWLP_USERDATA, 0);
      break;
  }
  return ::DefWindowProcW(window, message, wparam, lparam);
}
