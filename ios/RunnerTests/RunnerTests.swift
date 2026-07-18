import Flutter
import UIKit
import XCTest

class RunnerTests: XCTestCase {

  func testSceneLifecycleIsConfigured() throws {
    let manifest = try XCTUnwrap(
      Bundle.main.object(forInfoDictionaryKey: "UIApplicationSceneManifest") as? [String: Any]
    )
    let configurations = try XCTUnwrap(manifest["UISceneConfigurations"] as? [String: Any])
    let applicationScenes = try XCTUnwrap(
      configurations["UIWindowSceneSessionRoleApplication"] as? [[String: Any]]
    )
    let scene = try XCTUnwrap(applicationScenes.first)

    XCTAssertEqual(scene["UISceneConfigurationName"] as? String, "flutter")
    XCTAssertTrue(
      (scene["UISceneDelegateClassName"] as? String)?.hasSuffix(".SceneDelegate") == true
    )
  }
}
