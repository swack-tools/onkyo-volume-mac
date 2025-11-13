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

    /// Validates an IPv4 address format (strict, no whitespace; each octet 0-255)
    /// - Parameter ip: The IP address string to validate
    /// - Returns: True if the format is valid
    static func isValidIPAddress(_ ip: String) -> Bool {
        // Reject any whitespace
        if ip.rangeOfCharacter(from: .whitespacesAndNewlines) != nil { return false }

        // Split into exactly 4 octets, preserving empties to catch leading/trailing dots
        let parts = ip.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count != 4 { return false }

        for part in parts {
            // Non-empty, max 3 digits
            if part.isEmpty || part.count > 3 { return false }
            // All characters must be digits 0-9
            if part.contains(where: { $0 < "0" || $0 > "9" }) { return false }
            // Convert and range-check 0...255
            guard let value = Int(part), (0...255).contains(value) else { return false }
        }
        return true
    }
}
