import CloudPushSDK
import Flutter
import Foundation
import UIKit
import UserNotifications

final class RemotePushEventBridge {
  static let shared = RemotePushEventBridge()

  private let channelName = "ai.awiki.awikime/remote_push_events"
  private let pendingEventsKey = "awiki_remote_push_pending_events"
  private let maxPendingEvents = 32
  private let maxPendingAgeMilliseconds = 24 * 60 * 60 * 1000
  private let maxPersistedStringLength = 256
  private let envelopeKeys: Set<String> = ["v", "eid", "ty", "ts", "ir", "tr", "mid", "exp"]
  private let lock = NSLock()

  private var channel: FlutterMethodChannel?
  private var initialized = false
  private var observersRegistered = false
  private var pendingAcknowledgements: [[AnyHashable: Any]] = []
  private var preparedColdStartIdentifiers: Set<String> = []

  private init() {}

  var isConfigured: Bool {
    guard configBoolean("AWikiEmasEnabled") else { return false }
    return !configString("AWikiEmasAppKey").isEmpty
      && !configString("AWikiEmasAppSecret").isEmpty
  }

  func prepare(launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
    guard let userInfo = launchOptions?[.remoteNotification] as? [AnyHashable: Any] else { return }
    prepare(userInfo: userInfo)
  }

  func prepare(userInfo: [AnyHashable: Any]) {
    guard isAliyunNotification(userInfo) else { return }
    let identifier = coldStartIdentifier(userInfo)
    if let identifier, !preparedColdStartIdentifiers.insert(identifier).inserted {
      return
    }
    acknowledgeWhenReady(userInfo)
    emit(kind: "notification_opened", userInfo: userInfo)
  }

  func attach(to messenger: FlutterBinaryMessenger) {
    guard channel == nil else { return }
    let methodChannel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    methodChannel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
    channel = methodChannel
  }

  func isAliyunNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
    if userInfo["m"] != nil || userInfo["msgId"] != nil || userInfo["messageId"] != nil {
      return true
    }
    return envelopeKeys.contains { userInfo[$0] != nil }
  }

  func register(deviceToken: Data) {
    guard isConfigured else { return }
    CloudPushSDK.registerDevice(deviceToken, withCallback: { [weak self] callback in
      guard callback.success else { return }
      self?.emit(kind: "registration_changed", payload: [:])
    })
  }

  func handleRegistrationFailure(_ error: Error) {
    #if DEBUG
      NSLog("AWikiRemotePush: APNs registration failed (%@)", String(describing: type(of: error)))
    #endif
  }

  func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) {
    acknowledgeWhenReady(userInfo)
    emit(kind: "notification_received", userInfo: userInfo)
  }

  func handleForegroundNotification(_ userInfo: [AnyHashable: Any]) {
    acknowledgeWhenReady(userInfo)
    emit(kind: "notification_received_in_app", userInfo: userInfo)
  }

  func handleNotificationOpened(_ userInfo: [AnyHashable: Any]) {
    acknowledgeWhenReady(userInfo)
    emit(kind: "notification_opened", userInfo: userInfo)
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isConfigured":
      result(isConfigured)
    case "initialize":
      initialize(result: result)
    case "getDeviceId":
      let deviceId = CloudPushSDK.getDeviceId() ?? ""
      if configBoolean("AWikiEmasLogDeviceId") {
        #if DEBUG
          NSLog("AWikiRemotePush: EMAS DeviceId: %@", deviceId)
        #endif
      }
      result(deviceId)
    case "createNotificationChannel":
      result(["code": "10005"])
    case "loadPendingEvents":
      result(loadPendingEvents())
    case "acknowledgePendingEvents":
      let deliveryIds = Set((call.arguments as? [String]) ?? [])
      acknowledgePendingEvents(deliveryIds)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func initialize(result: @escaping FlutterResult) {
    guard isConfigured else {
      result(["code": "configuration_disabled"])
      return
    }
    if initialized {
      requestNotificationAuthorization()
      result(["code": "10000"])
      return
    }

    registerObserversIfNeeded()
    let appKey = configString("AWikiEmasAppKey")
    let appSecret = configString("AWikiEmasAppSecret")
    CloudPushSDK.start(withAppkey: appKey, appSecret: appSecret) { [weak self] callback in
      DispatchQueue.main.async {
        guard callback.success else {
          result([
            "code": "initialization_failed",
            "errorMsg": callback.error.map { String(describing: type(of: $0)) } ?? "CloudPushSDK",
          ])
          return
        }
        self?.initialized = true
        self?.flushPendingAcknowledgements()
        self?.requestNotificationAuthorization()
        self?.emit(kind: "registration_changed", payload: [:])
        result(["code": "10000"])
      }
    }
  }

  private func requestNotificationAuthorization() {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
      guard granted else { return }
      DispatchQueue.main.async {
        UIApplication.shared.registerForRemoteNotifications()
      }
    }
  }

  private func acknowledgeWhenReady(_ userInfo: [AnyHashable: Any]) {
    guard initialized else {
      pendingAcknowledgements = Array(
        (pendingAcknowledgements + [userInfo]).suffix(maxPendingEvents)
      )
      return
    }
    CloudPushSDK.sendNotificationAck(userInfo)
  }

  private func flushPendingAcknowledgements() {
    let pending = pendingAcknowledgements
    pendingAcknowledgements.removeAll(keepingCapacity: false)
    for userInfo in pending {
      CloudPushSDK.sendNotificationAck(userInfo)
    }
  }

  private func coldStartIdentifier(_ userInfo: [AnyHashable: Any]) -> String? {
    for key in ["m", "msgId", "messageId", "eid"] {
      if let value = boundedString(userInfo[key]) {
        return value
      }
    }
    return nil
  }

  private func registerObserversIfNeeded() {
    guard !observersRegistered else { return }
    observersRegistered = true
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(channelOpened),
      name: Notification.Name("CCPDidChannelConnectedSuccess"),
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(messageReceived(_:)),
      name: Notification.Name("CCPDidReceiveMessageNotification"),
      object: nil
    )
  }

  @objc private func channelOpened() {
    emit(kind: "registration_changed", payload: [:])
  }

  @objc private func messageReceived(_ notification: Notification) {
    let userInfo = notification.object as? [AnyHashable: Any] ?? [:]
    emit(kind: "message_received", userInfo: userInfo)
  }

  private func emit(kind: String, userInfo: [AnyHashable: Any]) {
    let normalized = userInfo.reduce(into: [String: Any]()) { output, entry in
      output[String(describing: entry.key)] = entry.value
    }
    var payload: [String: Any] = [:]
    let messageId = normalized["m"] ?? normalized["msgId"] ?? normalized["messageId"]
    if let messageId = boundedString(messageId) {
      payload["msgId"] = messageId
    }
    let envelope = sanitizeEnvelope(normalized["extraMap"] ?? normalized)
    if !envelope.isEmpty {
      payload["extraMap"] = envelope
    }
    emit(kind: kind, payload: payload)
  }

  private func emit(kind: String, payload: [String: Any]) {
    let event: [String: Any] = [
      "delivery_id": UUID().uuidString,
      "kind": kind,
      "payload": payload,
      "received_at_ms": currentTimeMilliseconds(),
    ]
    persist(event)
    DispatchQueue.main.async { [weak self] in
      self?.channel?.invokeMethod("onRemotePushEvents", arguments: [event])
    }
  }

  private func persist(_ event: [String: Any]) {
    guard let safeEvent = eventForPersistence(event) else { return }
    lock.lock()
    defer { lock.unlock() }
    let now = currentTimeMilliseconds()
    let existing = UserDefaults.standard.array(forKey: pendingEventsKey) as? [[String: Any]] ?? []
    var retained = existing.compactMap(eventForPersistence).filter { stored in
      guard let receivedAt = stored["received_at_ms"] as? Int else { return false }
      return now - receivedAt <= maxPendingAgeMilliseconds
    }
    retained = Array(retained.suffix(maxPendingEvents - 1))
    retained.append(safeEvent)
    UserDefaults.standard.set(retained, forKey: pendingEventsKey)
  }

  private func loadPendingEvents() -> [[String: Any]] {
    lock.lock()
    defer { lock.unlock() }
    let now = currentTimeMilliseconds()
    let stored = UserDefaults.standard.array(forKey: pendingEventsKey) as? [[String: Any]] ?? []
    let retained = stored.compactMap(eventForPersistence).filter { event in
      guard let receivedAt = event["received_at_ms"] as? Int else { return false }
      return now - receivedAt <= maxPendingAgeMilliseconds
    }
    UserDefaults.standard.set(retained, forKey: pendingEventsKey)
    return retained
  }

  private func acknowledgePendingEvents(_ deliveryIds: Set<String>) {
    guard !deliveryIds.isEmpty else { return }
    lock.lock()
    defer { lock.unlock() }
    let stored = UserDefaults.standard.array(forKey: pendingEventsKey) as? [[String: Any]] ?? []
    let retained = stored.filter { event in
      guard let deliveryId = event["delivery_id"] as? String else { return false }
      return !deliveryIds.contains(deliveryId)
    }
    UserDefaults.standard.set(retained, forKey: pendingEventsKey)
  }

  private func eventForPersistence(_ event: [String: Any]) -> [String: Any]? {
    guard
      let kind = event["kind"] as? String,
      kind == "notification_opened" || kind == "message_received",
      let deliveryId = boundedString(event["delivery_id"]),
      let receivedAt = event["received_at_ms"] as? Int
    else {
      return nil
    }
    let sourcePayload = event["payload"] as? [String: Any] ?? [:]
    var payload: [String: Any] = [:]
    if let messageId = boundedString(sourcePayload["msgId"]) {
      payload["msgId"] = messageId
    }
    let envelope = sanitizeEnvelope(sourcePayload["extraMap"])
    if !envelope.isEmpty {
      payload["extraMap"] = envelope
    }
    return [
      "delivery_id": deliveryId,
      "kind": kind,
      "payload": payload,
      "received_at_ms": receivedAt,
    ]
  }

  private func sanitizeEnvelope(_ value: Any?) -> [String: Any] {
    let source: [String: Any]
    if let map = value as? [String: Any] {
      source = map
    } else if
      let text = value as? String,
      let data = text.data(using: .utf8),
      let map = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    {
      source = map
    } else {
      return [:]
    }
    var sanitized: [String: Any] = [:]
    for key in envelopeKeys {
      if let text = boundedString(source[key]) {
        sanitized[key] = text
      } else if let number = source[key] as? NSNumber {
        sanitized[key] = number
      }
    }
    return sanitized
  }

  private func boundedString(_ value: Any?) -> String? {
    guard let value = value as? String, !value.isEmpty else { return nil }
    return String(value.prefix(maxPersistedStringLength))
  }

  private func configString(_ key: String) -> String {
    guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return "" }
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.contains("$(") ? "" : normalized
  }

  private func configBoolean(_ key: String) -> Bool {
    let value = configString(key).lowercased()
    return value == "yes" || value == "true" || value == "1"
  }

  private func currentTimeMilliseconds() -> Int {
    Int(Date().timeIntervalSince1970 * 1000)
  }
}
