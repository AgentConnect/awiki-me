import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerAttachmentChannel(flutterViewController: flutterViewController)

    super.awakeFromNib()
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
      default:
        result(FlutterMethodNotImplemented)
      }
    }
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
