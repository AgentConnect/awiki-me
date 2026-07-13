import Cocoa

final class MenuBarStatusController: NSObject {
  static let shared = MenuBarStatusController()

  private enum Layout {
    static let iconSize = NSSize(width: 18, height: 18)
    static let minimumItemWidth: CGFloat = 24
    static let unreadTextGap: CGFloat = 3
  }

  private var statusItem: NSStatusItem?
  // Keep the Flutter window alive after the user closes it. The app remains
  // running for its menu-bar status item, so a weak reference can disappear
  // before applicationShouldHandleReopen tries to restore the window.
  private var mainWindow: NSWindow?
  private var unreadCount = 0

  private override init() {
    super.init()
  }

  func configure(mainWindow: NSWindow) {
    self.mainWindow = mainWindow
    ensureStatusItem()
    renderStatusImage()
  }

  func setUnreadCount(_ count: Int) {
    let normalizedCount = max(0, count)
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      if unreadCount == normalizedCount {
        return
      }
      unreadCount = normalizedCount
      renderStatusImage()
    }
  }

  func restoreMainWindow() {
    DispatchQueue.main.async { [weak self] in
      self?.activateMainWindow()
    }
  }

  @objc private func statusItemClicked(_ sender: Any?) {
    activateMainWindow()
  }

  private func ensureStatusItem() {
    if statusItem != nil {
      return
    }
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem = item
    guard let button = item.button else {
      return
    }
    button.target = self
    button.action = #selector(statusItemClicked(_:))
    _ = button.sendAction(on: [.leftMouseUp])
    button.imagePosition = .imageLeft
    button.imageScaling = .scaleProportionallyDown
    button.toolTip = "AWikiMe"
  }

  private func activateMainWindow() {
    guard let window = targetWindow() else {
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    if NSApp.isHidden {
      NSApp.unhide(nil)
    }
    if window.isMiniaturized {
      window.deminiaturize(nil)
    }
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
    NSApp.activate(ignoringOtherApps: true)
  }

  private func targetWindow() -> NSWindow? {
    if let mainWindow {
      return mainWindow
    }
    if let window = NSApp.windows.first(where: { $0 is MainFlutterWindow }) {
      return window
    }
    return NSApp.mainWindow ?? NSApp.keyWindow
  }

  private func renderStatusImage() {
    ensureStatusItem()
    guard let button = statusItem?.button else {
      return
    }
    let label = badgeLabel(for: unreadCount)
    let image = menuBarMarkImage()
    button.image = image
    button.attributedTitle = unreadTitle(label)
    statusItem?.length = statusItemLength(label: label)
  }

  private func badgeLabel(for count: Int) -> String? {
    if count <= 0 {
      return nil
    }
    if count > 99 {
      return "99+"
    }
    return "\(count)"
  }

  private func menuBarMarkImage() -> NSImage {
    let image =
      NSImage(named: "MenuBarMark")
      ?? NSApp.applicationIconImage
      ?? NSImage(size: Layout.iconSize)
    image.size = Layout.iconSize
    image.isTemplate = true
    return image
  }

  private func unreadTitle(_ label: String?) -> NSAttributedString {
    guard let label else {
      return NSAttributedString(string: "")
    }
    return NSAttributedString(
      string: " \(label)",
      attributes: [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor.labelColor,
        .baselineOffset: 0,
      ]
    )
  }

  private func statusItemLength(label: String?) -> CGFloat {
    guard let label else {
      return Layout.minimumItemWidth
    }
    let labelWidth = (label as NSString).size(withAttributes: [
      .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    ]).width
    return Layout.iconSize.width
      + Layout.unreadTextGap
      + ceil(labelWidth)
      + 8
  }
}
