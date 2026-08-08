import XCTest
@testable import AIUsageMonitor

final class UpdateCheckerTests: XCTestCase {
    func test_manualUpdateCheckIsShownWhenAnotherCheckCanBeRequested() {
        XCTAssertTrue(UpdateStatus.unknown.showsManualUpdateCheck)
        XCTAssertTrue(UpdateStatus.upToDate.showsManualUpdateCheck)
        XCTAssertTrue(UpdateStatus.error("Network unavailable").showsManualUpdateCheck)
    }

    func test_manualUpdateCheckIsHiddenDuringAvailableUpdateFlow() {
        let downloadURL = URL(string: "https://example.com/AIUsageMonitor.dmg")!

        XCTAssertFalse(
            UpdateStatus.available(version: "v2.0.0", downloadURL: downloadURL)
                .showsManualUpdateCheck
        )
        XCTAssertFalse(UpdateStatus.downloading.showsManualUpdateCheck)
        XCTAssertFalse(UpdateStatus.readyToInstall.showsManualUpdateCheck)
    }
}
