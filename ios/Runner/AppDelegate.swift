import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, UIDocumentPickerDelegate {
  private let documentChannelName = "ai.awiki.awikime/document_picker"
  private var documentChannel: FlutterMethodChannel?
  private var pendingSaveData: Data?
  private var pendingSaveResult: FlutterResult?
  private var pendingPickResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    registerDocumentChannel()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func registerDocumentChannel() {
    guard documentChannel == nil else {
      return
    }
    guard let registrar = registrar(forPlugin: documentChannelName) else {
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
    }
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    if let result = pendingSaveResult {
      pendingSaveResult = nil
      pendingSaveData = nil
      result(urls.first?.absoluteString)
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

  private func presentFromTopController(_ controller: UIViewController) {
    guard let root = window?.rootViewController else {
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
      return
    }
    var top = root
    while let presented = top.presentedViewController {
      top = presented
    }
    top.present(controller, animated: true)
  }
}
