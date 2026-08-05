#ifndef RUNNER_WINDOW_PLACEMENT_H_
#define RUNNER_WINDOW_PLACEMENT_H_

#include <windows.h>

namespace awiki {

class WindowPlacementStore final {
 public:
  static void Restore(HWND window);
  static void Save(HWND window);
  static void Reset(HWND window);
  static SIZE MinimumTrackSize(HWND window, UINT dpi);
};

}  // namespace awiki

#endif  // RUNNER_WINDOW_PLACEMENT_H_
