import Flutter
import UIKit
import XCTest

class RunnerTests: XCTestCase {
  func testFlutterApplicationLaunches() {
    XCTAssertTrue(UIApplication.shared.delegate is FlutterAppDelegate)
  }
}
