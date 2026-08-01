import Foundation
import XCTest

final class AuthenticationColorContrastTests: XCTestCase {
    func testTextTokensKeepAccessibleContrastOnAuthenticationSurfaces() throws {
        let ink = try color(named: "AuthInk")
        let placeholder = try color(named: "AuthPlaceholder")
        let surface = try color(named: "AuthSurface")
        let background = try color(named: "AuthBackground")

        XCTAssertGreaterThanOrEqual(contrast(ink, surface), 7)
        XCTAssertGreaterThanOrEqual(contrast(ink, background), 7)
        XCTAssertGreaterThanOrEqual(contrast(placeholder, surface), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(placeholder, background), 4.5)
    }

    private func color(named name: String) throws -> RGBColor {
        let url = repositoryRoot
            .appendingPathComponent("Clovery/Assets.xcassets")
            .appendingPathComponent("\(name).colorset/Contents.json")
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let colors = try XCTUnwrap(object["colors"] as? [[String: Any]])
        let color = try XCTUnwrap(colors.first?["color"] as? [String: Any])
        let components = try XCTUnwrap(color["components"] as? [String: String])
        return RGBColor(
            red: try component("red", in: components),
            green: try component("green", in: components),
            blue: try component("blue", in: components)
        )
    }

    private func component(_ key: String, in values: [String: String]) throws -> Double {
        let value = try XCTUnwrap(values[key])
        let hex = value.hasPrefix("0x") ? String(value.dropFirst(2)) : value
        return Double(try XCTUnwrap(Int(hex, radix: 16))) / 255
    }

    private func contrast(_ foreground: RGBColor, _ background: RGBColor) -> Double {
        let lighter = max(foreground.luminance, background.luminance)
        let darker = min(foreground.luminance, background.luminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private struct RGBColor {
    let red: Double
    let green: Double
    let blue: Double

    var luminance: Double {
        0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    private func linear(_ value: Double) -> Double {
        value <= 0.04045
            ? value / 12.92
            : pow((value + 0.055) / 1.055, 2.4)
    }
}
