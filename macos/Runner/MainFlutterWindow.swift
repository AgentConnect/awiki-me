import Cocoa
import FlutterMacOS
import Security
import UniformTypeIdentifiers

class MainFlutterWindow: NSWindow {
  private let awikiErrAuthorizationDenied = OSStatus(-60008)
  private let scopeSecretQueue = DispatchQueue(label: "ai.awiki.awikime.scope-secret-keychain")

  private enum TrafficLightLayout {
    // Keep this aligned with the Flutter macOS rail width in app_shell.dart.
    static let railWidth: CGFloat = 72
    static let minimumRailWidth: CGFloat = 56
    static let minimumLeading: CGFloat = 6
    static let preferredLeading: CGFloat = 8
    static let minimumGap: CGFloat = 4
    static let preferredGap: CGFloat = 8
  }

  private var trafficLightRailWidth: CGFloat = TrafficLightLayout.railWidth

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    configureChrome()
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerWindowChromeChannel(flutterViewController: flutterViewController)
    registerMenuBarStatusChannel(flutterViewController: flutterViewController)
    registerAttachmentChannel(flutterViewController: flutterViewController)
    registerKeychainAccessChannel(flutterViewController: flutterViewController)
    registerScopeSecretChannel(flutterViewController: flutterViewController)
    MenuBarStatusController.shared.configure(mainWindow: self)

    super.awakeFromNib()
    scheduleTrafficLightLayout()
  }

  override func setFrame(_ frameRect: NSRect, display flag: Bool) {
    super.setFrame(frameRect, display: flag)
    scheduleTrafficLightLayout()
  }

  private func configureChrome() {
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    styleMask.insert(.fullSizeContentView)
    isMovableByWindowBackground = true
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleWindowFrameChanged),
      name: NSWindow.didResizeNotification,
      object: self
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleWindowFrameChanged),
      name: NSWindow.didEndLiveResizeNotification,
      object: self
    )
    scheduleTrafficLightLayout()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  @objc private func handleWindowFrameChanged() {
    scheduleTrafficLightLayout()
  }

  private func scheduleTrafficLightLayout() {
    DispatchQueue.main.async { [weak self] in
      self?.layoutTrafficLightButtons()
    }
  }

  private func layoutTrafficLightButtons() {
    guard
      let closeButton = standardWindowButton(.closeButton),
      let minimizeButton = standardWindowButton(.miniaturizeButton),
      let zoomButton = standardWindowButton(.zoomButton)
    else {
      return
    }

    let buttons = [closeButton, minimizeButton, zoomButton]
    let contentWidth = contentView?.bounds.width ?? frame.width
    let railWidth = min(
      max(TrafficLightLayout.minimumRailWidth, trafficLightRailWidth),
      max(TrafficLightLayout.minimumRailWidth, contentWidth)
    )
    let totalButtonWidth = buttons.reduce(CGFloat(0)) { result, button in
      result + button.frame.width
    }
    let maxGapForRail =
      (railWidth - totalButtonWidth - TrafficLightLayout.preferredLeading * 2) /
      CGFloat(buttons.count - 1)
    let gap = min(
      TrafficLightLayout.preferredGap,
      max(TrafficLightLayout.minimumGap, floor(maxGapForRail))
    )
    let groupWidth = totalButtonWidth + gap * CGFloat(buttons.count - 1)
    let leading = max(
      TrafficLightLayout.minimumLeading,
      floor((railWidth - groupWidth) / 2)
    )

    var x = leading
    for button in buttons {
      button.setFrameOrigin(NSPoint(x: x, y: button.frame.origin.y))
      x += button.frame.width + gap
    }
  }

  private func registerWindowChromeChannel(flutterViewController: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "ai.awiki.awikime/window_chrome",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "setTrafficLightRailWidth":
        self.setTrafficLightRailWidth(arguments: call.arguments, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func setTrafficLightRailWidth(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let args = arguments as? [String: Any],
      let width = args["width"] as? NSNumber
    else {
      result(FlutterError(code: "bad_args", message: "width is required", details: nil))
      return
    }
    trafficLightRailWidth = CGFloat(truncating: width)
    scheduleTrafficLightLayout()
    result(nil)
  }

  private func registerMenuBarStatusChannel(flutterViewController: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "ai.awiki.awikime/menu_bar_status",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "setUnreadCount":
        self.setMenuBarUnreadCount(arguments: call.arguments, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func setMenuBarUnreadCount(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let args = arguments as? [String: Any],
      let count = args["count"] as? NSNumber
    else {
      result(FlutterError(code: "bad_args", message: "count is required", details: nil))
      return
    }
    MenuBarStatusController.shared.setUnreadCount(count.intValue)
    result(nil)
  }

  private struct KeychainRequest {
    let service: String
    let account: String
    let value: String?
  }

  private struct ScopeSecretRequest {
    let service: String
    let account: String
    let value: String?
    let expectedRevision: Int?
  }

  private func registerKeychainAccessChannel(flutterViewController: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "ai.awiki.awikime/keychain_access",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "readGenericPassword":
        self.readGenericPassword(arguments: call.arguments, result: result)
      case "writeGenericPassword":
        self.writeGenericPassword(arguments: call.arguments, result: result)
      case "deleteGenericPassword":
        self.deleteGenericPassword(arguments: call.arguments, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func registerScopeSecretChannel(flutterViewController: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "ai.awiki.awikime/scope_secret",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "readScopeSecret":
        self.readScopeSecret(arguments: call.arguments, result: result)
      case "createScopeSecretExclusive":
        self.createScopeSecretExclusive(arguments: call.arguments, result: result)
      case "compareAndReplaceScopeSecret":
        self.compareAndReplaceScopeSecret(arguments: call.arguments, result: result)
      case "deleteScopeSecret":
        self.deleteScopeSecret(arguments: call.arguments, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func parseScopeSecretRequest(
    arguments: Any?,
    requireValue: Bool,
    requireExpectedRevision: Bool,
    result: FlutterResult
  ) -> ScopeSecretRequest? {
    guard
      let args = arguments as? [String: Any],
      let service = args["service"] as? String,
      isScopeServiceAllowedForCurrentApplication(service),
      let account = args["account"] as? String,
      isCanonicalScopeAccount(account)
    else {
      result(scopeSecretFlutterError(code: "scope_secret_bad_request", status: errSecParam))
      return nil
    }
    let value = args["value"] as? String
    if requireValue && value == nil {
      result(scopeSecretFlutterError(code: "scope_secret_bad_request", status: errSecParam))
      return nil
    }
    let revision = strictJsonInteger(args["expected_revision"])
    if requireExpectedRevision && (revision == nil || revision! < 1) {
      result(scopeSecretFlutterError(code: "scope_secret_bad_request", status: errSecParam))
      return nil
    }
    return ScopeSecretRequest(
      service: service,
      account: account,
      value: value,
      expectedRevision: revision
    )
  }

  private func isScopeServiceAllowedForCurrentApplication(_ service: String) -> Bool {
    switch Bundle.main.bundleIdentifier {
    case "ai.awiki.awikime":
      return service == "ai.awiki.awikime.scope-secrets"
    case "ai.awiki.awikime.dev":
      return service == "ai.awiki.awikime.dev.scope-secrets"
    default:
      return false
    }
  }

  private func isCanonicalScopeAccount(_ account: String) -> Bool {
    let pattern = #"^scope/[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"#
    return account.range(of: pattern, options: .regularExpression) != nil
  }

  private func readScopeSecret(arguments: Any?, result: @escaping FlutterResult) {
    guard let request = parseScopeSecretRequest(
      arguments: arguments,
      requireValue: false,
      requireExpectedRevision: false,
      result: result
    ) else { return }
    scopeSecretQueue.async {
      let response = self.readGenericPassword(service: request.service, account: request.account)
      DispatchQueue.main.async {
        switch response.status {
        case errSecSuccess:
          result(response.value)
        case errSecItemNotFound:
          result(nil)
        default:
          result(self.scopeSecretFlutterError(status: response.status))
        }
      }
    }
  }

  private func createScopeSecretExclusive(arguments: Any?, result: @escaping FlutterResult) {
    guard let request = parseScopeSecretRequest(
      arguments: arguments,
      requireValue: true,
      requireExpectedRevision: false,
      result: result
    ), let value = request.value else { return }
    scopeSecretQueue.async {
      guard self.validateScopeEnvelope(value, account: request.account, requiredRevision: 1) else {
        DispatchQueue.main.async {
          result(self.scopeSecretFlutterError(code: "scope_secret_corrupt", status: errSecDecode))
        }
        return
      }
      let status = self.addScopeSecretExclusive(
        service: request.service,
        account: request.account,
        value: value
      )
      DispatchQueue.main.async {
        if status == errSecSuccess {
          result(nil)
        } else if status == errSecDuplicateItem {
          result(self.scopeSecretFlutterError(code: "scope_secret_already_exists", status: status))
        } else {
          result(self.scopeSecretFlutterError(status: status))
        }
      }
    }
  }

  private func compareAndReplaceScopeSecret(arguments: Any?, result: @escaping FlutterResult) {
    guard let request = parseScopeSecretRequest(
      arguments: arguments,
      requireValue: true,
      requireExpectedRevision: true,
      result: result
    ), let value = request.value, let expectedRevision = request.expectedRevision else { return }
    scopeSecretQueue.async {
      let current = self.readGenericPassword(service: request.service, account: request.account)
      guard current.status == errSecSuccess, let currentValue = current.value else {
        DispatchQueue.main.async {
          if current.status == errSecItemNotFound {
            result(self.scopeSecretFlutterError(code: "scope_secret_revision_conflict", status: current.status))
          } else {
            result(self.scopeSecretFlutterError(status: current.status))
          }
        }
        return
      }
      guard self.validateScopeEnvelope(
        currentValue,
        account: request.account,
        requiredRevision: nil
      ) else {
        DispatchQueue.main.async {
          result(self.scopeSecretFlutterError(code: "scope_secret_corrupt", status: errSecDecode))
        }
        return
      }
      guard self.validateScopeEnvelope(
        value,
        account: request.account,
        requiredRevision: nil
      ) else {
        DispatchQueue.main.async {
          result(self.scopeSecretFlutterError(code: "scope_secret_corrupt", status: errSecDecode))
        }
        return
      }
      guard self.scopeEnvelopeRevision(currentValue) == expectedRevision else {
        DispatchQueue.main.async {
          result(self.scopeSecretFlutterError(code: "scope_secret_revision_conflict", status: errSecDuplicateItem))
        }
        return
      }
      guard self.scopeEnvelopeRevision(value) == expectedRevision + 1 else {
        DispatchQueue.main.async {
          result(self.scopeSecretFlutterError(code: "scope_secret_revision_conflict", status: errSecParam))
        }
        return
      }
      guard let data = value.data(using: .utf8) else {
        DispatchQueue.main.async {
          result(self.scopeSecretFlutterError(code: "scope_secret_corrupt", status: errSecDecode))
        }
        return
      }
      let query = self.baseGenericPasswordQuery(service: request.service, account: request.account)
      let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
      DispatchQueue.main.async {
        if status == errSecSuccess {
          result(nil)
        } else if status == errSecItemNotFound {
          result(self.scopeSecretFlutterError(code: "scope_secret_revision_conflict", status: status))
        } else {
          result(self.scopeSecretFlutterError(status: status))
        }
      }
    }
  }

  private func deleteScopeSecret(arguments: Any?, result: @escaping FlutterResult) {
    guard let request = parseScopeSecretRequest(
      arguments: arguments,
      requireValue: false,
      requireExpectedRevision: false,
      result: result
    ) else { return }
    scopeSecretQueue.async {
      let status = self.deleteGenericPassword(service: request.service, account: request.account)
      DispatchQueue.main.async {
        if status == errSecSuccess || status == errSecItemNotFound {
          result(nil)
        } else {
          result(self.scopeSecretFlutterError(status: status))
        }
      }
    }
  }

  private func addScopeSecretExclusive(service: String, account: String, value: String) -> OSStatus {
    guard let data = value.data(using: .utf8) else { return errSecParam }
    var add = baseGenericPasswordQuery(service: service, account: account)
    add[kSecValueData] = data
    if service == "ai.awiki.awikime.scope-secrets" {
      let accessResult = createCurrentBundleKeychainAccess()
      guard accessResult.status == errSecSuccess, let access = accessResult.access else {
        return accessResult.status
      }
      add[kSecAttrAccess] = access
    }
    // Development has an intentionally separate service and uses the standard
    // current-app ACL. Production never falls back when its explicit ACL fails.
    return SecItemAdd(add as CFDictionary, nil)
  }

  private func validateScopeEnvelope(
    _ value: String,
    account: String,
    requiredRevision: Int?
  ) -> Bool {
    guard
      let data = value.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data),
      let envelope = object as? [String: Any],
      Set(envelope.keys) == Set(["schema_version", "scope_id", "revision", "active_secrets"]),
      strictJsonInteger(envelope["schema_version"]) == 1,
      envelope["scope_id"] as? String == String(account.dropFirst("scope/".count)),
      let revision = strictJsonInteger(envelope["revision"]),
      revision >= 1,
      let activeSecrets = envelope["active_secrets"] as? [String: Any],
      Set(activeSecrets.keys) == Set(["identity_vault_root"]),
      let root = activeSecrets["identity_vault_root"] as? [String: Any],
      Set(root.keys) == Set(["key_id", "key_version", "algorithm", "material_b64"]),
      let keyId = root["key_id"] as? String,
      isCanonicalUuidV4(keyId),
      strictJsonInteger(root["key_version"]) == 1,
      root["algorithm"] as? String == "raw-256",
      let materialBase64 = root["material_b64"] as? String,
      let material = Data(base64Encoded: materialBase64),
      material.count == 32,
      material.base64EncodedString() == materialBase64
    else { return false }
    return requiredRevision == nil || revision == requiredRevision
  }

  private func strictJsonInteger(_ value: Any?) -> Int? {
    guard let number = value as? NSNumber else { return nil }
    if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
    let integer = number.intValue
    guard number.doubleValue == Double(integer) else { return nil }
    return integer
  }

  private func isCanonicalUuidV4(_ value: String) -> Bool {
    let pattern = #"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"#
    return value.range(of: pattern, options: .regularExpression) != nil
  }

  private func scopeEnvelopeRevision(_ value: String) -> Int? {
    guard
      let data = value.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data),
      let envelope = object as? [String: Any]
    else { return nil }
    return strictJsonInteger(envelope["revision"])
  }

  private func scopeSecretFlutterError(
    code: String? = nil,
    status: OSStatus
  ) -> FlutterError {
    let stableCode: String
    if let code {
      stableCode = code
    } else {
      switch status {
      case errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled, awikiErrAuthorizationDenied:
        stableCode = "scope_secret_access_denied"
      case errSecDecode:
        stableCode = "scope_secret_corrupt"
      case errSecNotAvailable:
        stableCode = "scope_secret_provider_unavailable"
      default:
        stableCode = "scope_secret_operation_failed"
      }
    }
    return FlutterError(
      code: stableCode,
      message: "Scope secret operation failed",
      details: status
    )
  }

  private func parseKeychainRequest(
    arguments: Any?,
    requireValue: Bool,
    result: FlutterResult
  ) -> KeychainRequest? {
    guard
      let args = arguments as? [String: Any],
      let service = args["service"] as? String,
      !service.isEmpty,
      let account = args["account"] as? String,
      !account.isEmpty
    else {
      result(FlutterError(code: "bad_args", message: "service and account are required", details: nil))
      return nil
    }
    let value = args["value"] as? String
    if requireValue && value == nil {
      result(FlutterError(code: "bad_args", message: "value is required", details: nil))
      return nil
    }
    return KeychainRequest(
      service: service,
      account: account,
      value: value
    )
  }

  private func readGenericPassword(arguments: Any?, result: @escaping FlutterResult) {
    guard let request = parseKeychainRequest(arguments: arguments, requireValue: false, result: result) else {
      return
    }
    DispatchQueue.global(qos: .utility).async {
      let response = self.readGenericPassword(service: request.service, account: request.account)
      DispatchQueue.main.async {
        switch response.status {
        case errSecSuccess:
          result(response.value)
        case errSecItemNotFound:
          result(nil)
        default:
          result(self.keychainFlutterError(code: "read_failed", status: response.status))
        }
      }
    }
  }

  private func writeGenericPassword(arguments: Any?, result: @escaping FlutterResult) {
    guard let request = parseKeychainRequest(arguments: arguments, requireValue: true, result: result) else {
      return
    }
    DispatchQueue.global(qos: .utility).async {
      let status = self.writeGenericPassword(
        service: request.service,
        account: request.account,
        value: request.value ?? ""
      )
      DispatchQueue.main.async {
        if status == errSecSuccess {
          result(nil)
          return
        }
        result(self.keychainFlutterError(code: "write_failed", status: status))
      }
    }
  }

  private func deleteGenericPassword(arguments: Any?, result: @escaping FlutterResult) {
    guard let request = parseKeychainRequest(arguments: arguments, requireValue: false, result: result) else {
      return
    }
    DispatchQueue.global(qos: .utility).async {
      let status = self.deleteGenericPassword(service: request.service, account: request.account)
      DispatchQueue.main.async {
        if status == errSecSuccess || status == errSecItemNotFound {
          result(nil)
          return
        }
        result(self.keychainFlutterError(code: "delete_failed", status: status))
      }
    }
  }

  private func baseGenericPasswordQuery(service: String, account: String) -> [CFString: Any] {
    return [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
    ]
  }

  private func readGenericPassword(service: String, account: String) -> (status: OSStatus, value: String?) {
    var query = baseGenericPasswordQuery(service: service, account: account)
    query[kSecReturnData] = true
    query[kSecMatchLimit] = kSecMatchLimitOne

    var ref: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &ref)
    guard status == errSecSuccess else {
      return (status, nil)
    }
    guard
      let data = ref as? Data,
      let value = String(data: data, encoding: .utf8)
    else {
      return (errSecDecode, nil)
    }
    return (status, value)
  }

  private func writeGenericPassword(service: String, account: String, value: String) -> OSStatus {
    guard let data = value.data(using: .utf8) else {
      return errSecParam
    }
    let accessResult = createCurrentBundleKeychainAccess()
    if accessResult.status == errSecSuccess, let access = accessResult.access {
      let accessStatus = writeGenericPassword(
        service: service,
        account: account,
        data: data,
        access: access
      )
      if accessStatus != awikiErrAuthorizationDenied {
        return accessStatus
      }
    } else if accessResult.status != awikiErrAuthorizationDenied {
      return accessResult.status
    }

    // Some local debug/test runners cannot obtain Authorization Services
    // permission for a custom SecAccess ACL (OSStatus -60008). Fall back to the
    // system's default Keychain ACL so migration can still move values out of
    // the legacy flutter_secure_storage service instead of touching the old item
    // on every launch.
    return writeGenericPassword(
      service: service,
      account: account,
      data: data,
      access: nil
    )
  }

  private func writeGenericPassword(
    service: String,
    account: String,
    data: Data,
    access: SecAccess?
  ) -> OSStatus {
    var add = baseGenericPasswordQuery(service: service, account: account)
    add[kSecValueData] = data
    if let access {
      add[kSecAttrAccess] = access
    }

    let addStatus = SecItemAdd(add as CFDictionary, nil)
    if addStatus != errSecDuplicateItem {
      return addStatus
    }

    let query = baseGenericPasswordQuery(service: service, account: account)
    let update: [CFString: Any] = [kSecValueData: data]
    // Do not refresh kSecAttrAccess for existing items during ordinary writes.
    // Updating an item's ACL/owner is what makes macOS show
    // "AWiki Me wants to change access permissions" Keychain prompts. New items
    // still receive the current executable ACL on SecItemAdd; existing items keep
    // their established ACL and only the secret value is replaced.
    return SecItemUpdate(query as CFDictionary, update as CFDictionary)
  }

  private func deleteGenericPassword(service: String, account: String) -> OSStatus {
    let query = baseGenericPasswordQuery(service: service, account: account)
    return SecItemDelete(query as CFDictionary)
  }

  private func createCurrentBundleKeychainAccess() -> (status: OSStatus, access: SecAccess?) {
    let accessDescription = "AWiki Me secure storage" as CFString
    // Trust the executable path instead of the .app bundle directory. Keychain
    // ACL checks are made against the process executable; using the bundle path
    // can leave items readable only after a per-launch authorization prompt.
    let trustedPath = Bundle.main.executablePath ?? Bundle.main.bundlePath
    var trustedApp: SecTrustedApplication?
    let trustedStatus = trustedPath.withCString { path in
      SecTrustedApplicationCreateFromPath(path, &trustedApp)
    }
    guard trustedStatus == errSecSuccess, let trustedApp else {
      return (trustedStatus, nil)
    }

    var access: SecAccess?
    let accessStatus = SecAccessCreate(
      accessDescription,
      [trustedApp] as CFArray,
      &access
    )
    guard accessStatus == errSecSuccess, let access else {
      return (accessStatus, nil)
    }
    return (errSecSuccess, access)
  }

  private func keychainFlutterError(code: String, status: OSStatus) -> FlutterError {
    let errorMessage = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown security result code"
    return FlutterError(
      code: code,
      message: "SecKeychain operation failed: \(status), \(errorMessage)",
      details: status
    )
  }

  private func registerAttachmentChannel(flutterViewController: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "ai.awiki.awikime/attachment_picker",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "pickAttachment":
        self.pickAttachment(result: result)
      case "saveAttachment":
        self.saveAttachment(arguments: call.arguments, result: result)
      case "setMainWindowVisible":
        self.setMainWindowVisible(arguments: call.arguments, result: result)
      case "isShiftPressed":
        result(NSEvent.modifierFlags.contains(.shift))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func setMainWindowVisible(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let args = arguments as? [String: Any],
      let visible = args["visible"] as? Bool
    else {
      result(FlutterError(code: "bad_args", message: "visible is required", details: nil))
      return
    }
    if visible {
      makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    } else {
      orderOut(nil)
    }
    result(nil)
  }

  private func pickAttachment(result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.resolvesAliases = true
    panel.beginSheetModal(for: self) { response in
      guard response == .OK, let url = panel.url else {
        result(nil)
        return
      }
      let values = try? url.resourceValues(forKeys: [.fileSizeKey])
      let filename = url.lastPathComponent.isEmpty ? "attachment" : url.lastPathComponent
      let mimeType: String
      if #available(macOS 11.0, *) {
        let typeValues = try? url.resourceValues(forKeys: [.contentTypeKey])
        mimeType = typeValues?.contentType?.preferredMIMEType ?? "application/octet-stream"
      } else {
        mimeType = "application/octet-stream"
      }
      do {
        let cachedUrl = try self.copyAttachmentToTemporaryDirectory(sourceUrl: url, filename: filename)
        result([
          "filename": filename,
          "mime_type": mimeType,
          "size_bytes": values?.fileSize ?? self.fileSize(at: cachedUrl),
          "path": cachedUrl.path,
        ])
      } catch {
        result(FlutterError(code: "pick_failed", message: error.localizedDescription, details: nil))
      }
    }
  }

  private func copyAttachmentToTemporaryDirectory(sourceUrl: URL, filename: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("awiki-attachments", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    cleanupOldAttachmentTempFiles(in: directory)
    let safeName = sanitizedFileName(filename.isEmpty ? "attachment" : filename)
    let destination = directory.appendingPathComponent("\(UUID().uuidString)-\(safeName)")
    try FileManager.default.copyItem(at: sourceUrl, to: destination)
    return destination
  }

  private func sanitizedFileName(_ value: String) -> String {
    let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
    let parts = value.components(separatedBy: invalid)
    let joined = parts.joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
    if joined.isEmpty {
      return "attachment"
    }
    return String(joined.prefix(160))
  }

  private func fileSize(at url: URL) -> Int {
    let values = try? url.resourceValues(forKeys: [.fileSizeKey])
    return values?.fileSize ?? 0
  }

  private func cleanupOldAttachmentTempFiles(in directory: URL) {
    guard
      let urls = try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return
    }
    let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
    for url in urls {
      let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
      if let modifiedAt = values?.contentModificationDate, modifiedAt < cutoff {
        try? FileManager.default.removeItem(at: url)
      }
    }
  }

  private func saveAttachment(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let args = arguments as? [String: Any],
      let filename = args["filename"] as? String,
      let bytes = args["bytes"] as? FlutterStandardTypedData
    else {
      result(FlutterError(code: "save_failed", message: "filename 和 bytes 为必填参数。", details: nil))
      return
    }
    let panel = NSSavePanel()
    panel.nameFieldStringValue = filename.isEmpty ? "attachment" : filename
    if #available(macOS 11.0, *),
       let mimeType = args["mime_type"] as? String,
       let contentType = UTType(mimeType: mimeType) {
      panel.allowedContentTypes = [contentType]
    }
    panel.beginSheetModal(for: self) { response in
      guard response == .OK, let url = panel.url else {
        result(nil)
        return
      }
      do {
        try bytes.data.write(to: url, options: .atomic)
        result(url.path)
      } catch {
        result(FlutterError(code: "save_failed", message: error.localizedDescription, details: nil))
      }
    }
  }
}
