import Flutter
import UIKit
import UniformTypeIdentifiers
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate {
  private let documentChannelName = "ai.awiki.awikime/document_picker"
  private let attachmentChannelName = "ai.awiki.awikime/attachment_picker"
  private var documentChannel: FlutterMethodChannel?
  private var attachmentChannel: FlutterMethodChannel?
  private var pendingSaveData: Data?
  private var pendingSaveResult: FlutterResult?
  private var pendingPickResult: FlutterResult?
  private var pendingAttachmentPickResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    RemotePushEventBridge.shared.prepare(launchOptions: launchOptions)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    let registry = engineBridge.pluginRegistry
    GeneratedPluginRegistrant.register(with: registry)
    registerDocumentChannel(with: registry)
    registerAttachmentChannel(with: registry)
    registerRemotePushChannel(with: registry)
  }

  private func registerRemotePushChannel(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "AWikiRemotePush") else {
      return
    }
    RemotePushEventBridge.shared.attach(to: registrar.messenger())
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    RemotePushEventBridge.shared.register(deviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
    RemotePushEventBridge.shared.handleRegistrationFailure(error)
  }

  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    guard RemotePushEventBridge.shared.isAliyunNotification(userInfo) else {
      super.application(
        application,
        didReceiveRemoteNotification: userInfo,
        fetchCompletionHandler: completionHandler
      )
      return
    }
    RemotePushEventBridge.shared.handleRemoteNotification(userInfo)
    completionHandler(.newData)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let userInfo = notification.request.content.userInfo
    guard RemotePushEventBridge.shared.isAliyunNotification(userInfo) else {
      super.userNotificationCenter(
        center,
        willPresent: notification,
        withCompletionHandler: completionHandler
      )
      return
    }
    RemotePushEventBridge.shared.handleForegroundNotification(userInfo)
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .badge, .sound])
    } else {
      completionHandler([.alert, .badge, .sound])
    }
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    guard RemotePushEventBridge.shared.isAliyunNotification(userInfo) else {
      super.userNotificationCenter(
        center,
        didReceive: response,
        withCompletionHandler: completionHandler
      )
      return
    }
    RemotePushEventBridge.shared.handleNotificationOpened(userInfo)
    completionHandler()
  }

  private func registerDocumentChannel(with registry: FlutterPluginRegistry) {
    guard documentChannel == nil else {
      return
    }
    guard let registrar = registry.registrar(forPlugin: documentChannelName) else {
      return
    }
    let channel = FlutterMethodChannel(
      name: documentChannelName,
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "saveZipFile":
        guard
          let args = call.arguments as? [String: Any],
          let fileName = args["file_name"] as? String,
          let bytes = args["bytes"] as? FlutterStandardTypedData
        else {
          result(
            FlutterError(
              code: "save_failed",
              message: "file_name 和 bytes 为必填参数。",
              details: nil
            )
          )
          return
        }
        self.presentExportPicker(fileName: fileName, data: bytes.data, result: result)
      case "pickZipFile":
        self.presentImportPicker(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    documentChannel = channel
  }

  private func registerAttachmentChannel(with registry: FlutterPluginRegistry) {
    guard attachmentChannel == nil else {
      return
    }
    guard let registrar = registry.registrar(forPlugin: attachmentChannelName) else {
      return
    }
    let channel = FlutterMethodChannel(
      name: attachmentChannelName,
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "pickAttachment":
        self.presentAttachmentPicker(result: result)
      case "saveAttachment":
        guard
          let args = call.arguments as? [String: Any],
          let fileName = args["filename"] as? String,
          let bytes = args["bytes"] as? FlutterStandardTypedData
        else {
          result(
            FlutterError(
              code: "save_failed",
              message: "filename 和 bytes 为必填参数。",
              details: nil
            )
          )
          return
        }
        self.presentExportPicker(fileName: fileName, data: bytes.data, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    attachmentChannel = channel
  }

  private func presentExportPicker(fileName: String, data: Data, result: @escaping FlutterResult) {
    guard pendingSaveResult == nil else {
      result(FlutterError(code: "save_in_progress", message: "已有导出任务正在进行。", details: nil))
      return
    }
    let tempUrl = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    do {
      try data.write(to: tempUrl, options: .atomic)
      pendingSaveData = data
      pendingSaveResult = result
      let picker = UIDocumentPickerViewController(url: tempUrl, in: .exportToService)
      picker.delegate = self
      picker.modalPresentationStyle = .formSheet
      presentFromTopController(picker)
    } catch {
      result(FlutterError(code: "save_failed", message: error.localizedDescription, details: nil))
    }
  }

  private func presentImportPicker(result: @escaping FlutterResult) {
    guard pendingPickResult == nil else {
      result(FlutterError(code: "pick_in_progress", message: "已有导入任务正在进行。", details: nil))
      return
    }
    pendingPickResult = result
    let picker = UIDocumentPickerViewController(
      documentTypes: ["public.zip-archive"],
      in: .import
    )
    picker.delegate = self
    picker.modalPresentationStyle = .formSheet
    presentFromTopController(picker)
  }

  private func presentAttachmentPicker(result: @escaping FlutterResult) {
    guard pendingAttachmentPickResult == nil else {
      result(FlutterError(code: "pick_in_progress", message: "已有文件选择任务正在进行。", details: nil))
      return
    }
    pendingAttachmentPickResult = result
    let picker: UIDocumentPickerViewController
    if #available(iOS 14.0, *) {
      picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.item], asCopy: true)
    } else {
      picker = UIDocumentPickerViewController(documentTypes: ["public.item"], in: .import)
    }
    picker.delegate = self
    picker.modalPresentationStyle = .formSheet
    presentFromTopController(picker)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    if let result = pendingSaveResult {
      pendingSaveResult = nil
      pendingSaveData = nil
      result(nil)
      return
    }
    if let result = pendingPickResult {
      pendingPickResult = nil
      result(nil)
      return
    }
    if let result = pendingAttachmentPickResult {
      pendingAttachmentPickResult = nil
      result(nil)
    }
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    if let result = pendingSaveResult {
      pendingSaveResult = nil
      pendingSaveData = nil
      result(urls.first?.absoluteString)
      return
    }
    if let result = pendingAttachmentPickResult {
      pendingAttachmentPickResult = nil
      guard let url = urls.first else {
        result(nil)
        return
      }
      readAttachment(url: url, result: result)
      return
    }
    guard let result = pendingPickResult else {
      return
    }
    pendingPickResult = nil
    guard let url = urls.first else {
      result(nil)
      return
    }
    let accessGranted = url.startAccessingSecurityScopedResource()
    defer {
      if accessGranted {
        url.stopAccessingSecurityScopedResource()
      }
    }
    do {
      let data = try Data(contentsOf: url)
      result(FlutterStandardTypedData(bytes: data))
    } catch {
      result(FlutterError(code: "pick_failed", message: error.localizedDescription, details: nil))
    }
  }

  private func readAttachment(url: URL, result: @escaping FlutterResult) {
    let accessGranted = url.startAccessingSecurityScopedResource()
    defer {
      if accessGranted {
        url.stopAccessingSecurityScopedResource()
      }
    }
    do {
      let values = try? url.resourceValues(forKeys: [.fileSizeKey])
      let filename = url.lastPathComponent.isEmpty ? "attachment" : url.lastPathComponent
      let mimeType: String
      if #available(iOS 14.0, *) {
        let typeValues = try? url.resourceValues(forKeys: [.contentTypeKey])
        mimeType = typeValues?.contentType?.preferredMIMEType ?? "application/octet-stream"
      } else {
        mimeType = "application/octet-stream"
      }
      let cachedUrl = try copyAttachmentToTemporaryDirectory(sourceUrl: url, filename: filename)
      result([
        "filename": filename,
        "mime_type": mimeType,
        "size_bytes": values?.fileSize ?? fileSize(at: cachedUrl),
        "path": cachedUrl.path,
      ])
    } catch {
      result(FlutterError(code: "pick_failed", message: error.localizedDescription, details: nil))
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

  private func presentFromTopController(_ controller: UIViewController) {
    let sceneWindows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
    let activeWindow = sceneWindows.first(where: \.isKeyWindow)
      ?? sceneWindows.first(where: { !$0.isHidden })
      ?? window
    guard let root = activeWindow?.rootViewController else {
      if let saveResult = pendingSaveResult {
        pendingSaveResult = nil
        pendingSaveData = nil
        saveResult(
          FlutterError(code: "save_failed", message: "当前无法打开导出面板。", details: nil)
        )
      }
      if let pickResult = pendingPickResult {
        pendingPickResult = nil
        pickResult(
          FlutterError(code: "pick_failed", message: "当前无法打开导入面板。", details: nil)
        )
      }
      if let attachmentPickResult = pendingAttachmentPickResult {
        pendingAttachmentPickResult = nil
        attachmentPickResult(
          FlutterError(code: "pick_failed", message: "当前无法打开文件选择面板。", details: nil)
        )
      }
      return
    }
    var top = root
    while let presented = top.presentedViewController {
      top = presented
    }
    top.present(controller, animated: true)
  }
}
