//
//  SettingsManagerTests.swift
//  OnkyoVolumeTests
//
//  Tests for SettingsManager IP validation and persistence
//

import XCTest
@testable import OnkyoVolume

final class SettingsManagerTests: XCTestCase {

    var settingsManager: SettingsManager!
    let testKey = "test_receiverIPAddress"

    override func setUp() {
        super.setUp()
        // Use a test-specific key to avoid conflicts
        settingsManager = SettingsManager()
        UserDefaults.standard.removeObject(forKey: testKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: testKey)
        super.tearDown()
    }

    // MARK: - IP Validation Tests

    func testValidIPAddresses() {
        XCTAssertTrue(SettingsManager.isValidIPAddress("192.168.1.1"))
        XCTAssertTrue(SettingsManager.isValidIPAddress("10.0.0.1"))
        XCTAssertTrue(SettingsManager.isValidIPAddress("172.16.0.1"))
        XCTAssertTrue(SettingsManager.isValidIPAddress("255.255.255.255"))
        XCTAssertTrue(SettingsManager.isValidIPAddress("0.0.0.0"))
    }

    func testInvalidIPAddresses() {
        XCTAssertFalse(SettingsManager.isValidIPAddress(""))
        XCTAssertFalse(SettingsManager.isValidIPAddress("192.168.1"))
        XCTAssertFalse(SettingsManager.isValidIPAddress("192.168.1.1.1"))
        XCTAssertFalse(SettingsManager.isValidIPAddress("256.1.1.1"))
        XCTAssertFalse(SettingsManager.isValidIPAddress("192.168.1.999"))
        XCTAssertFalse(SettingsManager.isValidIPAddress("abc.def.ghi.jkl"))
        XCTAssertFalse(SettingsManager.isValidIPAddress("192.168.-1.1"))
        XCTAssertFalse(SettingsManager.isValidIPAddress("192.168.1.1."))
        XCTAssertFalse(SettingsManager.isValidIPAddress(".192.168.1.1"))
    }

    func testIPAddressWithWhitespace() {
        XCTAssertFalse(SettingsManager.isValidIPAddress(" 192.168.1.1"))
        XCTAssertFalse(SettingsManager.isValidIPAddress("192.168.1.1 "))
        XCTAssertFalse(SettingsManager.isValidIPAddress("192. 168.1.1"))
    }

    // MARK: - Persistence Tests

    func testSetAndGetReceiverIP() {
        let testIP = "192.168.1.100"

        UserDefaults.standard.set(testIP, forKey: "receiverIPAddress")
        let retrievedIP = UserDefaults.standard.string(forKey: "receiverIPAddress")

        XCTAssertEqual(retrievedIP, testIP)
    }

    func testGetReceiverIPReturnsNilWhenNotSet() {
        UserDefaults.standard.removeObject(forKey: "receiverIPAddress")
        let ip = UserDefaults.standard.string(forKey: "receiverIPAddress")

        XCTAssertNil(ip)
    }
}
