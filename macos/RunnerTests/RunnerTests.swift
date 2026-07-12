import Cocoa
import FlutterMacOS
import XCTest
@testable import AWiki_Me

class RunnerTests: XCTestCase {

  func testScopeSecretKeychainLabelsAreFriendlyAndChannelSpecific() {
    XCTAssertEqual(
      ScopeSecretKeychainPresentation.applicationLabel(for: "ai.awiki.awikime"),
      "AWiki Me secure storage"
    )
    XCTAssertEqual(
      ScopeSecretKeychainPresentation.applicationLabel(for: "ai.awiki.awikime.dev"),
      "AWiki Me secure storage (Development)"
    )
    XCTAssertNil(
      ScopeSecretKeychainPresentation.applicationLabel(for: "untrusted.bundle")
    )
    XCTAssertEqual(
      ScopeSecretKeychainPresentation.label(for: "ai.awiki.awikime.scope-secrets"),
      "AWiki Me secure storage"
    )
    XCTAssertEqual(
      ScopeSecretKeychainPresentation.label(for: "ai.awiki.awikime.dev.scope-secrets"),
      "AWiki Me secure storage (Development)"
    )
    XCTAssertNil(ScopeSecretKeychainPresentation.label(for: "untrusted.service"))
  }

}
