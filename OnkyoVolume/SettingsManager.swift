//
//  SettingsManager.swift
//  OnkyoVolume
//
//  Manages persistent storage of application settings using UserDefaults.
//

import Foundation

/// Manages application settings persistence
class SettingsManager {

    // MARK: - Constants

    private enum Keys {
        static let receiverIPAddress = "receiverIPAddress"
    }

    // MARK: - Singleton

    static let shared = SettingsManager()

    private let userDefaults: UserDefaults

    // MARK: - Initialization

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // MARK: - Public Methods

    /// Retrieves the saved receiver IP address
    /// - Returns: The IP address string, or nil if not set
    func getReceiverIP() -> String? {
        return userDefaults.string(forKey: Keys.receiverIPAddress)
    }

    /// Saves the receiver IP address
    /// - Parameter ip: The IP address to save
    func setReceiverIP(_ ip: String) {
        userDefaults.set(ip, forKey: Keys.receiverIPAddress)
    }

    /// Validates an IP address format
    /// - Parameter ip: The IP address string to validate
    /// - Returns: True if the format is valid
    static func isValidIPAddress(_ ip: String) -> Bool {
        let pattern = "^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: ip.utf16.count)
        return regex?.firstMatch(in: ip, range: range) != nil
    }
}
