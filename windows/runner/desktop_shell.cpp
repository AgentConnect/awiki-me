#include "desktop_shell.h"

#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <windows.h>

#include <algorithm>
#include <array>
#include <climits>
#include <cstdint>
#include <filesystem>
#include <memory>
#include <string>

#include "app_constants.h"
#include "resource.h"
#include "utils.h"

namespace {

constexpr wchar_t kTrayTooltip[] = L"AWiki Me";
constexpr wchar_t kTrayOpenLabel[] = L"Open AWiki Me";
constexpr wchar_t kTrayExitLabel[] = L"Exit";

int ReadCount(const flutter::EncodableValue* arguments) {
  if (arguments == nullptr) {
    return 0;
  }
  const auto* map = std::get_if<flutter::EncodableMap>(arguments);
  if (map == nullptr) {
    return 0;
  }
  const auto iterator = map->find(flutter::EncodableValue("count"));
  if (iterator == map->end()) {
    return 0;
  }
  if (const auto* value = std::get_if<int32_t>(&iterator->second)) {
    return *value;
  }
  if (const auto* value = std::get_if<int64_t>(&iterator->second)) {
    return static_cast<int>(std::clamp<int64_t>(*value, 0, INT_MAX));
  }
  return 0;
}

std::optional<std::wstring> LocalAppDataPath() {
  PWSTR raw_path = nullptr;
  const HRESULT status = ::SHGetKnownFolderPath(
      FOLDERID_LocalAppData, KF_FLAG_DEFAULT, nullptr, &raw_path);
  if (FAILED(status) || raw_path == nullptr) {
    if (raw_path != nullptr) {
      ::CoTaskMemFree(raw_path);
    }
    return std::nullopt;
  }
  std::wstring value(raw_path);
  ::CoTaskMemFree(raw_path);
  return value;
}

std::optional<std::wstring> TemporaryPath() {
  const DWORD required = ::GetTempPathW(0, nullptr);
  if (required == 0) {
    return std::nullopt;
  }
  std::wstring buffer(required, L'\0');
  const DWORD written = ::GetTempPathW(required, buffer.data());
  if (written == 0 || written >= required) {
    return std::nullopt;
  }
  buffer.resize(written);
  return buffer;
}

flutter::EncodableValue Utf8Path(const std::filesystem::path& path) {
  return flutter::EncodableValue(Utf8FromUtf16(path.c_str()));
}

}  // namespace

DesktopShell::DesktopShell(HWND window, flutter::FlutterEngine* engine)
    : window_(window) {
  activate_message_ = ::RegisterWindowMessageW(awiki::kActivateMessageName);
  shutdown_for_update_message_ =
      ::RegisterWindowMessageW(awiki::kShutdownForUpdateMessageName);
  taskbar_created_message_ = ::RegisterWindowMessageW(L"TaskbarCreated");
  taskbar_button_created_message_ =
      ::RegisterWindowMessageW(L"TaskbarButtonCreated");

  InitializeTaskbar();
  RegisterMethodChannel(engine);
  CreateTrayIcon();
}

DesktopShell::~DesktopShell() {
  if (channel_ != nullptr) {
    channel_->SetMethodCallHandler(nullptr);
    channel_.reset();
  }
  RemoveTrayIcon();
  if (taskbar_ != nullptr) {
    taskbar_->SetOverlayIcon(window_, nullptr, L"");
    taskbar_->Release();
    taskbar_ = nullptr;
  }
  if (overlay_icon_ != nullptr) {
    ::DestroyIcon(overlay_icon_);
    overlay_icon_ = nullptr;
  }
}

void DesktopShell::RegisterMethodChannel(flutter::FlutterEngine* engine) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      engine->messenger(), awiki::kDesktopShellChannel,
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const std::string& method = call.method_name();
        if (method == "showWindow") {
          ActivateWindow();
          result->Success();
          return;
        }
        if (method == "hideWindow") {
          HideWindow();
          result->Success();
          return;
        }
        if (method == "setUnreadCount") {
          UpdateUnreadCount(ReadCount(call.arguments()));
          result->Success();
          return;
        }
        if (method == "ready") {
          dart_ready_ = true;
          if (!pending_exit_type_.empty()) {
            SendShellEvent(pending_exit_type_.c_str());
          }
          result->Success();
          return;
        }
        if (method == "getStorageRoots") {
          const flutter::EncodableMap roots = GetStorageRoots();
          if (roots.empty()) {
            result->Error("windows_known_folder_unavailable",
                          "Windows storage roots are unavailable");
          } else {
            result->Success(flutter::EncodableValue(roots));
          }
          return;
        }
        if (method == "completeExit") {
          if (!exit_requested_) {
            result->Error("desktop_shell_exit_not_requested",
                          "No desktop shell exit is pending");
            return;
          }
          if (exit_completed_) {
            result->Success();
            return;
          }
          if (::PostMessageW(window_, awiki::kExitReadyMessage, 0, 0) ==
              FALSE) {
            result->Error("desktop_shell_exit_failed",
                          "The desktop shell could not complete exit");
            return;
          }
          exit_completed_ = true;
          result->Success();
          return;
        }
        result->NotImplemented();
      });
}

void DesktopShell::InitializeTaskbar() {
  if (taskbar_ != nullptr) {
    taskbar_->Release();
    taskbar_ = nullptr;
  }

  ITaskbarList3* taskbar = nullptr;
  const HRESULT create_status = ::CoCreateInstance(
      CLSID_TaskbarList, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&taskbar));
  if (FAILED(create_status) || taskbar == nullptr) {
    return;
  }
  if (FAILED(taskbar->HrInit())) {
    taskbar->Release();
    return;
  }
  taskbar_ = taskbar;
}

void DesktopShell::CreateTrayIcon() {
  tray_icon_ = {};
  tray_icon_.cbSize = static_cast<DWORD>(sizeof(tray_icon_));
  tray_icon_.hWnd = window_;
  tray_icon_.uID = 1;
  tray_icon_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP;
  tray_icon_.uCallbackMessage = awiki::kTrayCallbackMessage;
  tray_icon_.hIcon = static_cast<HICON>(
      ::LoadImageW(::GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON),
                   IMAGE_ICON, ::GetSystemMetrics(SM_CXSMICON),
                   ::GetSystemMetrics(SM_CYSMICON), LR_DEFAULTCOLOR));
  ::wcsncpy_s(tray_icon_.szTip, kTrayTooltip, _TRUNCATE);
  tray_icon_added_ = ::Shell_NotifyIconW(NIM_ADD, &tray_icon_) != FALSE;
  if (tray_icon_added_) {
    tray_icon_.uVersion = NOTIFYICON_VERSION_4;
    tray_icon_uses_version_4_ =
        ::Shell_NotifyIconW(NIM_SETVERSION, &tray_icon_) != FALSE;
  }
}

void DesktopShell::RemoveTrayIcon() {
  if (tray_icon_added_) {
    ::Shell_NotifyIconW(NIM_DELETE, &tray_icon_);
    tray_icon_added_ = false;
  }
  tray_icon_uses_version_4_ = false;
  if (tray_icon_.hIcon != nullptr) {
    ::DestroyIcon(tray_icon_.hIcon);
    tray_icon_.hIcon = nullptr;
  }
}

void DesktopShell::ShowTrayMenu() {
  HMENU menu = ::CreatePopupMenu();
  if (menu == nullptr) {
    return;
  }
  ::AppendMenuW(menu, MF_STRING, awiki::kTrayOpenCommand, kTrayOpenLabel);
  ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  ::AppendMenuW(menu, MF_STRING, awiki::kTrayExitCommand, kTrayExitLabel);
  POINT cursor{};
  ::GetCursorPos(&cursor);
  ::SetForegroundWindow(window_);
  ::TrackPopupMenu(menu, TPM_RIGHTBUTTON | TPM_BOTTOMALIGN | TPM_LEFTALIGN,
                   cursor.x, cursor.y, 0, window_, nullptr);
  ::PostMessageW(window_, WM_NULL, 0, 0);
  ::DestroyMenu(menu);
}

void DesktopShell::ActivateWindow() {
  if (::IsIconic(window_)) {
    ::ShowWindow(window_, SW_RESTORE);
  } else {
    ::ShowWindow(window_, SW_SHOW);
  }
  ::SetForegroundWindow(window_);
  ::BringWindowToTop(window_);
}

void DesktopShell::HideWindow() {
  ::ShowWindow(window_, SW_HIDE);
}

void DesktopShell::RequestExit(const char* event_type) {
  if (exit_requested_) {
    return;
  }
  exit_requested_ = true;
  pending_exit_type_ = event_type;
  if (dart_ready_) {
    SendShellEvent(event_type);
  }
}

void DesktopShell::SendShellEvent(const char* event_type) {
  if (channel_ == nullptr) {
    return;
  }
  flutter::EncodableMap arguments;
  arguments[flutter::EncodableValue("type")] =
      flutter::EncodableValue(event_type);
  channel_->InvokeMethod("shellEvent",
                         std::make_unique<flutter::EncodableValue>(arguments));
}

std::optional<LRESULT> DesktopShell::HandleWindowMessage(UINT message,
                                                         WPARAM wparam,
                                                         LPARAM lparam) {
  if (activate_message_ != 0 && message == activate_message_ &&
      wparam == awiki::kIpcMessageCookie) {
    ActivateWindow();
    SendShellEvent("activate");
    return 0;
  }
  if (shutdown_for_update_message_ != 0 &&
      message == shutdown_for_update_message_ &&
      wparam == awiki::kIpcMessageCookie) {
    RequestExit("shutdownForUpdate");
    return 0;
  }
  if (taskbar_created_message_ != 0 && message == taskbar_created_message_) {
    RemoveTrayIcon();
    CreateTrayIcon();
    InitializeTaskbar();
    ApplyTaskbarOverlay();
    return 0;
  }
  if (taskbar_button_created_message_ != 0 &&
      message == taskbar_button_created_message_) {
    ApplyTaskbarOverlay();
    return 0;
  }

  switch (message) {
    case WM_CLOSE:
      HideWindow();
      return 0;
    case WM_COMMAND:
      switch (LOWORD(wparam)) {
        case awiki::kTrayOpenCommand:
          ActivateWindow();
          return 0;
        case awiki::kTrayExitCommand:
          RequestExit("requestExit");
          return 0;
      }
      break;
    case awiki::kTrayCallbackMessage: {
      if (tray_icon_uses_version_4_ &&
          static_cast<UINT>(HIWORD(lparam)) != tray_icon_.uID) {
        return 0;
      }
      const UINT event = tray_icon_uses_version_4_
                             ? static_cast<UINT>(LOWORD(lparam))
                             : static_cast<UINT>(lparam);
      switch (event) {
        case NIN_SELECT:
        case NIN_KEYSELECT:
        case WM_LBUTTONDBLCLK:
          ActivateWindow();
          return 0;
        case WM_CONTEXTMENU:
        case WM_RBUTTONUP:
          ShowTrayMenu();
          return 0;
      }
      break;
    }
  }
  return std::nullopt;
}

void DesktopShell::UpdateUnreadCount(int count) {
  unread_count_ = std::clamp(count, 0, 1000000);
  ApplyTaskbarOverlay();
}

void DesktopShell::ApplyTaskbarOverlay() {
  if (taskbar_ == nullptr || window_ == nullptr) {
    return;
  }
  if (overlay_icon_ != nullptr) {
    taskbar_->SetOverlayIcon(window_, nullptr, L"");
    ::DestroyIcon(overlay_icon_);
    overlay_icon_ = nullptr;
  }
  if (unread_count_ <= 0) {
    taskbar_->SetOverlayIcon(window_, nullptr, L"");
    return;
  }
  overlay_icon_ = CreateUnreadOverlayIcon(unread_count_);
  if (overlay_icon_ == nullptr) {
    return;
  }
  const std::wstring description =
      unread_count_ > 99 ? L"99+ unread messages"
                         : std::to_wstring(unread_count_) + L" unread messages";
  taskbar_->SetOverlayIcon(window_, overlay_icon_, description.c_str());
}

HICON DesktopShell::CreateUnreadOverlayIcon(int count) const {
  constexpr int kSize = 32;
  BITMAPV5HEADER header{};
  header.bV5Size = static_cast<DWORD>(sizeof(header));
  header.bV5Width = kSize;
  header.bV5Height = -kSize;
  header.bV5Planes = 1;
  header.bV5BitCount = 32;
  header.bV5Compression = BI_BITFIELDS;
  header.bV5RedMask = 0x00FF0000;
  header.bV5GreenMask = 0x0000FF00;
  header.bV5BlueMask = 0x000000FF;
  header.bV5AlphaMask = 0xFF000000;

  HDC screen = ::GetDC(nullptr);
  if (screen == nullptr) {
    return nullptr;
  }
  void* pixel_data = nullptr;
  HBITMAP color_bitmap =
      ::CreateDIBSection(screen, reinterpret_cast<BITMAPINFO*>(&header),
                         DIB_RGB_COLORS, &pixel_data, nullptr, 0);
  HDC canvas = ::CreateCompatibleDC(screen);
  ::ReleaseDC(nullptr, screen);
  if (color_bitmap == nullptr || canvas == nullptr || pixel_data == nullptr) {
    if (color_bitmap != nullptr) {
      ::DeleteObject(color_bitmap);
    }
    if (canvas != nullptr) {
      ::DeleteDC(canvas);
    }
    return nullptr;
  }

  ::SecureZeroMemory(pixel_data, kSize * kSize * sizeof(uint32_t));

  HGDIOBJ old_bitmap = ::SelectObject(canvas, color_bitmap);
  HBRUSH badge_brush = ::CreateSolidBrush(RGB(220, 38, 38));
  HPEN badge_pen = ::CreatePen(PS_SOLID, 1, RGB(255, 255, 255));
  const std::wstring label = count > 99 ? L"99+" : std::to_wstring(count);
  const int font_height = label.size() > 2 ? -13 : -17;
  HFONT font = ::CreateFontW(font_height, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
                             DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                             CLIP_DEFAULT_PRECIS, ANTIALIASED_QUALITY,
                             DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
  if (old_bitmap == nullptr || badge_brush == nullptr || badge_pen == nullptr ||
      font == nullptr) {
    if (old_bitmap != nullptr) {
      ::SelectObject(canvas, old_bitmap);
    }
    if (font != nullptr) {
      ::DeleteObject(font);
    }
    if (badge_pen != nullptr) {
      ::DeleteObject(badge_pen);
    }
    if (badge_brush != nullptr) {
      ::DeleteObject(badge_brush);
    }
    ::DeleteDC(canvas);
    ::DeleteObject(color_bitmap);
    return nullptr;
  }

  ::SetBkMode(canvas, TRANSPARENT);
  HGDIOBJ old_brush = ::SelectObject(canvas, badge_brush);
  HGDIOBJ old_pen = ::SelectObject(canvas, badge_pen);
  HGDIOBJ old_font = ::SelectObject(canvas, font);
  if (old_brush == nullptr || old_pen == nullptr || old_font == nullptr) {
    if (old_font != nullptr) {
      ::SelectObject(canvas, old_font);
    }
    if (old_pen != nullptr) {
      ::SelectObject(canvas, old_pen);
    }
    if (old_brush != nullptr) {
      ::SelectObject(canvas, old_brush);
    }
    ::SelectObject(canvas, old_bitmap);
    ::DeleteObject(font);
    ::DeleteObject(badge_pen);
    ::DeleteObject(badge_brush);
    ::DeleteDC(canvas);
    ::DeleteObject(color_bitmap);
    return nullptr;
  }

  ::Ellipse(canvas, 1, 1, kSize - 1, kSize - 1);

  ::SetTextColor(canvas, RGB(255, 255, 255));
  RECT text_rect{1, 1, kSize - 1, kSize - 1};
  ::DrawTextW(canvas, label.c_str(), static_cast<int>(label.size()), &text_rect,
              DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);

  auto* pixels = static_cast<uint32_t*>(pixel_data);
  for (int index = 0; index < kSize * kSize; ++index) {
    if ((pixels[index] & 0x00FFFFFF) != 0) {
      pixels[index] |= 0xFF000000;
    }
  }

  ::SelectObject(canvas, old_font);
  ::SelectObject(canvas, old_pen);
  ::SelectObject(canvas, old_brush);
  ::SelectObject(canvas, old_bitmap);
  ::DeleteObject(font);
  ::DeleteObject(badge_pen);
  ::DeleteObject(badge_brush);
  ::DeleteDC(canvas);

  std::array<uint8_t, (kSize * kSize) / CHAR_BIT> mask_bits{};
  HBITMAP mask_bitmap = ::CreateBitmap(kSize, kSize, 1, 1, mask_bits.data());
  if (mask_bitmap == nullptr) {
    ::DeleteObject(color_bitmap);
    return nullptr;
  }
  ICONINFO icon_info{};
  icon_info.fIcon = TRUE;
  icon_info.hbmColor = color_bitmap;
  icon_info.hbmMask = mask_bitmap;
  HICON icon = ::CreateIconIndirect(&icon_info);
  ::DeleteObject(mask_bitmap);
  ::DeleteObject(color_bitmap);
  return icon;
}

flutter::EncodableMap DesktopShell::GetStorageRoots() const {
  const auto local_app_data = LocalAppDataPath();
  const auto temporary = TemporaryPath();
  if (!local_app_data.has_value() || !temporary.has_value()) {
    return {};
  }
  const std::filesystem::path product_root =
      std::filesystem::path(*local_app_data) / L"AWiki" / L"AWikiMe";
  const std::filesystem::path temp_root =
      std::filesystem::path(*temporary) / L"AWikiMe";
  flutter::EncodableMap roots;
  roots[flutter::EncodableValue("support")] =
      Utf8Path(product_root / L"support");
  roots[flutter::EncodableValue("cache")] = Utf8Path(product_root / L"cache");
  roots[flutter::EncodableValue("temp")] = Utf8Path(temp_root);
  return roots;
}
