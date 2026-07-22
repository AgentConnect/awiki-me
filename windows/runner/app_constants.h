#ifndef RUNNER_APP_CONSTANTS_H_
#define RUNNER_APP_CONSTANTS_H_

#include <windows.h>

namespace awiki {

inline constexpr wchar_t kWindowClassName[] =
    L"AI_AWIKI_AWIKIME_FLUTTER_WINDOW";
inline constexpr wchar_t kWindowTitle[] = L"AWiki Me";
inline constexpr wchar_t kSingleInstanceMutexName[] =
    L"Local\\ai.awiki.awikime.single-instance";
inline constexpr wchar_t kActivateMessageName[] =
    L"ai.awiki.awikime.activate.v1";
inline constexpr wchar_t kShutdownForUpdateMessageName[] =
    L"ai.awiki.awikime.shutdown-for-update.v1";
inline constexpr WPARAM kIpcMessageCookie = 0x41574B49;  // "AWKI"

inline constexpr wchar_t kAppUserModelId[] = L"AWiki.AWikiMe";
inline constexpr char kToastActivatorGuid[] =
    "42f66431-9bea-46c4-ac14-475b9044a2be";

inline constexpr char kDesktopShellChannel[] = "ai.awiki.awikime/desktop_shell";
inline constexpr char kAttachmentPickerChannel[] =
    "ai.awiki.awikime/attachment_picker";
inline constexpr char kScopeSecretChannel[] = "ai.awiki.awikime/scope_secret";

inline constexpr UINT kTrayCallbackMessage = WM_APP + 0x31;
inline constexpr UINT kExitReadyMessage = WM_APP + 0x32;
inline constexpr UINT kTrayOpenCommand = 0x7101;
inline constexpr UINT kTrayExitCommand = 0x7102;

}  // namespace awiki

#endif  // RUNNER_APP_CONSTANTS_H_
