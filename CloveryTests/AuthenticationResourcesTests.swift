import UIKit
import XCTest
@testable import Clovery

final class AuthenticationResourcesTests: XCTestCase {
    func testAuthenticationAssetsResolveFromBundle() {
        for asset in AuthenticationAsset.allCases {
            XCTAssertNotNil(UIImage(named: asset.rawValue), "Missing asset: \(asset.rawValue)")
        }
    }

    func testGaeguFontsAreRegistered() {
        XCTAssertNotNil(UIFont(name: "Gaegu-Regular", size: 24))
        XCTAssertNotNil(UIFont(name: "Gaegu-Light", size: 16))
        XCTAssertNotNil(UIFont(name: "Gaegu-Bold", size: 24))
    }
}
