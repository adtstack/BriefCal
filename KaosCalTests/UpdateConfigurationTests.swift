import Foundation
import XCTest
@testable import KaosCal

final class UpdateConfigurationTests: XCTestCase {
    private let validPublicKey = Data(repeating: 0x2A, count: 32)
        .base64EncodedString()

    func testLoadsValidHTTPSConfiguration() throws {
        let configuration = try XCTUnwrap(UpdateConfiguration.load(from: [
            "SUFeedURL": "https://updates.example.com/kaoscal/appcast.xml",
            "SUPublicEDKey": validPublicKey
        ]))

        XCTAssertEqual(
            configuration.feedURL,
            URL(string: "https://updates.example.com/kaoscal/appcast.xml")
        )
        XCTAssertEqual(configuration.publicKey, validPublicKey)
    }

    func testRejectsMissingConfiguration() {
        XCTAssertNil(UpdateConfiguration.load(from: [:]))
        XCTAssertNil(UpdateConfiguration.load(from: [
            "SUFeedURL": "",
            "SUPublicEDKey": ""
        ]))
    }

    func testRejectsInsecureOrMalformedConfiguration() {
        XCTAssertNil(UpdateConfiguration.load(from: [
            "SUFeedURL": "http://updates.example.com/appcast.xml",
            "SUPublicEDKey": validPublicKey
        ]))
        XCTAssertNil(UpdateConfiguration.load(from: [
            "SUFeedURL": "https://updates.example.com/appcast.xml",
            "SUPublicEDKey": "not-a-key"
        ]))
        XCTAssertNil(UpdateConfiguration.load(from: [
            "SUFeedURL": "https://updates.example.com/appcast.xml",
            "SUPublicEDKey": Data(repeating: 0x2A, count: 31).base64EncodedString()
        ]))
    }
}
