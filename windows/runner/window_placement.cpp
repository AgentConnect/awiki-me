#include "window_placement.h"

#include <flutter_windows.h>

#include <algorithm>
#include <climits>
#include <cstdint>

namespace awiki {
namespace {

#ifdef AWIKI_RELEASE_SCOPE
constexpr wchar_t kRegistryPath[] = L"Software\\AWiki\\AWikiMe";
#else
constexpr wchar_t kRegistryPath[] = L"Software\\AWiki\\AWikiMeDevelopment";
#endif
constexpr wchar_t kRegistryValue[] = L"MainWindowPlacementV2";
constexpr wchar_t kLegacyRegistryValue[] = L"MainWindowPlacementV1";
constexpr DWORD kPlacementVersion = 2;
constexpr LONG kMinimumClientWidthDip = 360;
constexpr LONG kMinimumClientHeightDip = 600;
constexpr LONG kDefaultClientWidthDip = 1280;
constexpr LONG kDefaultClientHeightDip = 800;

struct StoredWindowPlacement {
  DWORD version;
  UINT dpi;
  WINDOWPLACEMENT placement;
};

UINT MonitorDpi(HMONITOR monitor) {
  const UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  return dpi == 0 ? USER_DEFAULT_SCREEN_DPI : dpi;
}

UINT NormalizeDpi(UINT dpi) {
  return dpi == 0 ? USER_DEFAULT_SCREEN_DPI : dpi;
}

LONG DipToPixels(LONG dips, UINT dpi) {
  const UINT normalized_dpi = NormalizeDpi(dpi);
  return ::MulDiv(dips, static_cast<int>(normalized_dpi),
                  USER_DEFAULT_SCREEN_DPI);
}

SIZE LogicalClientToTrackSize(HWND window,
                              LONG width_dip,
                              LONG height_dip,
                              UINT dpi) {
  const UINT normalized_dpi = NormalizeDpi(dpi);
  RECT rect{0, 0, DipToPixels(width_dip, normalized_dpi),
            DipToPixels(height_dip, normalized_dpi)};
  const DWORD style = static_cast<DWORD>(::GetWindowLongPtr(window, GWL_STYLE));
  const DWORD ex_style =
      static_cast<DWORD>(::GetWindowLongPtr(window, GWL_EXSTYLE));
  if (!::AdjustWindowRectExForDpi(&rect, style, FALSE, ex_style,
                                  normalized_dpi)) {
    ::AdjustWindowRectEx(&rect, style, FALSE, ex_style);
  }
  return SIZE{rect.right - rect.left, rect.bottom - rect.top};
}

bool ReadPlacement(StoredWindowPlacement* stored) {
  HKEY key = nullptr;
  if (::RegOpenKeyExW(HKEY_CURRENT_USER, kRegistryPath, 0, KEY_QUERY_VALUE,
                      &key) != ERROR_SUCCESS) {
    return false;
  }
  DWORD type = 0;
  DWORD size = sizeof(*stored);
  const LSTATUS status = ::RegQueryValueExW(
      key, kRegistryValue, nullptr, &type,
      reinterpret_cast<BYTE*>(stored), &size);
  ::RegCloseKey(key);
  return status == ERROR_SUCCESS && type == REG_BINARY &&
         size == sizeof(*stored) && stored->version == kPlacementVersion &&
         stored->placement.length == sizeof(WINDOWPLACEMENT);
}

void WritePlacement(const StoredWindowPlacement& stored) {
  HKEY key = nullptr;
  if (::RegCreateKeyExW(HKEY_CURRENT_USER, kRegistryPath, 0, nullptr, 0,
                        KEY_SET_VALUE, nullptr, &key,
                        nullptr) != ERROR_SUCCESS) {
    return;
  }
  ::RegSetValueExW(key, kRegistryValue, 0, REG_BINARY,
                   reinterpret_cast<const BYTE*>(&stored), sizeof(stored));
  ::RegDeleteValueW(key, kLegacyRegistryValue);
  ::RegCloseKey(key);
}

bool IsValidRect(const RECT& rect) {
  const int64_t width = static_cast<int64_t>(rect.right) - rect.left;
  const int64_t height = static_cast<int64_t>(rect.bottom) - rect.top;
  return width > 0 && height > 0 && width <= INT_MAX && height <= INT_MAX;
}

RECT ClampToWorkArea(HWND window,
                     RECT rect,
                     const RECT& work_area,
                     UINT dpi,
                     bool center) {
  const SIZE minimum = WindowPlacementStore::MinimumTrackSize(window, dpi);
  const LONG available_width = work_area.right - work_area.left;
  const LONG available_height = work_area.bottom - work_area.top;
  LONG width = rect.right - rect.left;
  LONG height = rect.bottom - rect.top;
  width = std::min(std::max(width, minimum.cx), available_width);
  height = std::min(std::max(height, minimum.cy), available_height);

  LONG left = rect.left;
  LONG top = rect.top;
  if (center) {
    left = work_area.left + (available_width - width) / 2;
    top = work_area.top + (available_height - height) / 2;
  } else {
    left = std::clamp(left, work_area.left, work_area.right - width);
    top = std::clamp(top, work_area.top, work_area.bottom - height);
  }
  return RECT{left, top, left + width, top + height};
}

MONITORINFO MonitorInfo(HMONITOR monitor) {
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  ::GetMonitorInfoW(monitor, &info);
  return info;
}

void ApplyDefaultWindowPlacement(HWND window, bool restore_window) {
  HMONITOR monitor = ::MonitorFromWindow(window, MONITOR_DEFAULTTOPRIMARY);
  if (monitor == nullptr) {
    return;
  }
  const MONITORINFO monitor_info = MonitorInfo(monitor);
  const UINT dpi = MonitorDpi(monitor);
  const SIZE desired =
      LogicalClientToTrackSize(window, kDefaultClientWidthDip,
                               kDefaultClientHeightDip, dpi);
  RECT frame{0, 0, desired.cx, desired.cy};
  frame = ClampToWorkArea(window, frame, monitor_info.rcWork, dpi, true);
  if (restore_window) {
    ::ShowWindow(window, SW_RESTORE);
  }
  ::SetWindowPos(window, nullptr, frame.left, frame.top,
                 frame.right - frame.left, frame.bottom - frame.top,
                 SWP_NOACTIVATE | SWP_NOZORDER);
  WindowPlacementStore::Save(window);
}

}  // namespace

void WindowPlacementStore::Restore(HWND window) {
  StoredWindowPlacement stored{};
  if (!ReadPlacement(&stored) || !IsValidRect(stored.placement.rcNormalPosition)) {
    ApplyDefaultWindowPlacement(window, false);
    return;
  }

  RECT restored = stored.placement.rcNormalPosition;
  HMONITOR monitor = ::MonitorFromRect(&restored, MONITOR_DEFAULTTONULL);
  const bool monitor_missing = monitor == nullptr;
  if (monitor_missing) {
    monitor = ::MonitorFromWindow(window, MONITOR_DEFAULTTOPRIMARY);
  }
  if (monitor == nullptr) {
    return;
  }
  const MONITORINFO monitor_info = MonitorInfo(monitor);
  const UINT target_dpi = MonitorDpi(monitor);
  if (stored.dpi != 0 && stored.dpi != target_dpi) {
    const LONG width = ::MulDiv(restored.right - restored.left, target_dpi,
                                stored.dpi);
    const LONG height = ::MulDiv(restored.bottom - restored.top, target_dpi,
                                 stored.dpi);
    restored.right = restored.left + width;
    restored.bottom = restored.top + height;
  }
  restored = ClampToWorkArea(window, restored, monitor_info.rcWork,
                             target_dpi, monitor_missing);

  WINDOWPLACEMENT placement{};
  placement.length = sizeof(placement);
  placement.showCmd = stored.placement.showCmd == SW_SHOWMAXIMIZED
                          ? SW_SHOWMAXIMIZED
                          : SW_SHOWNORMAL;
  placement.rcNormalPosition = restored;
  ::SetWindowPlacement(window, &placement);
}

void WindowPlacementStore::Save(HWND window) {
  if (window == nullptr || !::IsWindow(window)) {
    return;
  }
  WINDOWPLACEMENT placement{};
  placement.length = sizeof(placement);
  if (!::GetWindowPlacement(window, &placement) ||
      !IsValidRect(placement.rcNormalPosition)) {
    return;
  }
  placement.flags = 0;
  placement.showCmd = ::IsZoomed(window) ? SW_SHOWMAXIMIZED : SW_SHOWNORMAL;
  WritePlacement(StoredWindowPlacement{
      kPlacementVersion,
      ::GetDpiForWindow(window),
      placement,
  });
}

void WindowPlacementStore::Reset(HWND window) {
  HKEY key = nullptr;
  if (::RegOpenKeyExW(HKEY_CURRENT_USER, kRegistryPath, 0, KEY_SET_VALUE,
                      &key) == ERROR_SUCCESS) {
    ::RegDeleteValueW(key, kRegistryValue);
    ::RegDeleteValueW(key, kLegacyRegistryValue);
    ::RegCloseKey(key);
  }
  ApplyDefaultWindowPlacement(window, true);
}

SIZE WindowPlacementStore::MinimumTrackSize(HWND window, UINT dpi) {
  return LogicalClientToTrackSize(window, kMinimumClientWidthDip,
                                  kMinimumClientHeightDip, dpi);
}

}  // namespace awiki
