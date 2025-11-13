//
//  OnkyoClient.swift
//  OnkyoVolume
//
//  Implements the eISCP (Ethernet-based Integra Serial Control Protocol) for
//  communicating with Onkyo receivers.
//

import Foundation
import Network

/// Errors that can occur during eISCP communication
enum OnkyoClientError: Error, LocalizedError {
    case connectionFailed
    case timeout
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return "Could not connect to receiver"
        case .timeout:
            return "Connection timed out"
        case .invalidResponse:
            return "Invalid response from receiver"
        }
    }
}

/// Thread-safe wrapper for tracking continuation state
private final class ResumedState: @unchecked Sendable {
    private let lock = NSLock()
    private var _resumed = false

    func checkAndSet() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if _resumed {
            return true
        }
        _resumed = true
        return false
    }
}

/// Client for communicating with Onkyo receivers via eISCP protocol
class OnkyoClient {

    // MARK: - Constants

    private static let defaultPort: UInt16 = 60128
    private static let connectionTimeout: TimeInterval = 10.0 // Increased for multiple responses

    // MARK: - Commands

    enum Command: String {
        case volumeUp = "MVLUP"
        case volumeDown = "MVLDOWN"
        case volumeQuery = "MVLQSTN"
    }

    // MARK: - Public Methods

    /// Sends a command to the Onkyo receiver
    /// - Parameters:
    ///   - command: The command to send
    ///   - host: The receiver's IP address
    /// - Throws: OnkyoClientError if the connection or send fails
    func sendCommand(_ command: Command, to host: String) async throws {
        try await sendRawCommand(command.rawValue, to: host)
    }

    /// Queries the current volume level from the receiver
    /// - Parameter host: The receiver's IP address
    /// - Returns: The volume level (0-100)
    /// - Throws: OnkyoClientError if the query fails
    func queryVolume(from host: String) async throws -> Int {
        // Keep reading responses until we get one with "MVL"
        let response = try await sendQueryCommand("MVLQSTN", to: host, expectingPrefix: "MVL")

        // Debug: Print raw response
        print("DEBUG: Raw volume response: \(response.debugDescription)")
        print("DEBUG: Response bytes: \(response.data(using: .utf8)?.map { String(format: "%02X", $0) }.joined(separator: " ") ?? "nil")")

        // Response format: "!1MVL{hex}\r\n" or "MVL{hex}"
        let cleaned = response.replacingOccurrences(of: "!1", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespaces)

        print("DEBUG: Cleaned response: \(cleaned)")

        // Extract hex value after "MVL"
        if cleaned.hasPrefix("MVL") {
            let hexString = String(cleaned.dropFirst(3))
            print("DEBUG: Hex string: \(hexString)")
            if let hexValue = Int(hexString, radix: 16) {
                print("DEBUG: Parsed volume: \(hexValue)")
                // Onkyo receivers typically use 0x00-0x64 (0-100 decimal)
                // Some models use 0x00-0x50 (0-80 decimal)
                // We'll map to 0-100 range
                return min(hexValue, 100)
            }
        }
        print("DEBUG: Failed to parse volume response")
        throw OnkyoClientError.invalidResponse
    }

    /// Sets the receiver volume to an absolute level
    /// - Parameters:
    ///   - volume: The volume level (0-100)
    ///   - host: The receiver's IP address
    /// - Throws: OnkyoClientError if the command fails
    func setVolume(_ volume: Int, to host: String) async throws {
        let clampedVolume = max(0, min(100, volume))
        let hexValue = String(format: "%02X", clampedVolume)
        try await sendRawCommand("MVL\(hexValue)", to: host)
    }

    // MARK: - Private Methods

    /// Sends a raw eISCP command string
    private func sendRawCommand(_ command: String, to host: String) async throws {
        // Build the eISCP packet
        let packet = buildPacket(for: command)

        // Create dedicated queue for this connection
        let queue = DispatchQueue(label: "com.swack-tools.onkyo-volume.command-\(UUID().uuidString)")

        // Create connection
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: Self.defaultPort),
            using: .tcp
        )

        // Set up state monitoring
        return try await withCheckedThrowingContinuation { continuation in
            let state = ResumedState()

            connection.stateUpdateHandler = { connectionState in
                switch connectionState {
                case .ready:
                    // Connection established, send the packet
                    connection.send(content: packet, completion: .contentProcessed { error in
                        if error != nil {
                            if !state.checkAndSet() {
                                continuation.resume(throwing: OnkyoClientError.connectionFailed)
                            }
                        } else {
                            // Command sent successfully
                            connection.cancel()
                            if !state.checkAndSet() {
                                continuation.resume()
                            }
                        }
                    })

                case .failed(_):
                    connection.cancel()
                    if !state.checkAndSet() {
                        continuation.resume(throwing: OnkyoClientError.connectionFailed)
                    }

                case .waiting(_):
                    // Network is unavailable
                    connection.cancel()
                    if !state.checkAndSet() {
                        continuation.resume(throwing: OnkyoClientError.connectionFailed)
                    }

                default:
                    break
                }
            }

            // Start the connection
            connection.start(queue: queue)

            // Set up timeout
            queue.asyncAfter(deadline: .now() + Self.connectionTimeout) {
                if !state.checkAndSet() {
                    connection.cancel()
                    continuation.resume(throwing: OnkyoClientError.timeout)
                }
            }
        }
    }

    /// Sends a query command and waits for a response matching the expected prefix
    /// Reads up to 5 responses to handle receivers that send status updates first
    private func sendQueryCommand(_ command: String, to host: String, expectingPrefix: String = "") async throws -> String {
        // Build the eISCP packet
        let packet = buildPacket(for: command)

        // Create dedicated queue for this connection
        let queue = DispatchQueue(label: "com.swack-tools.onkyo-volume.query-\(UUID().uuidString)")

        // Create connection
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: Self.defaultPort),
            using: .tcp
        )

        // Helper to read one response
        func readOneResponse() async throws -> String? {
            return try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 16, maximumLength: 16) { headerData, _, _, headerError in
                    guard headerError == nil, let headerData = headerData, headerData.count == 16 else {
                        continuation.resume(throwing: OnkyoClientError.invalidResponse)
                        return
                    }

                    // Parse header to get data size
                    let dataSizeBytes = headerData[8..<12]
                    let dataSize = dataSizeBytes.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

                    // Read the message data
                    connection.receive(minimumIncompleteLength: Int(dataSize), maximumLength: Int(dataSize)) { messageData, _, _, messageError in
                        guard messageError == nil, let messageData = messageData else {
                            continuation.resume(throwing: OnkyoClientError.invalidResponse)
                            return
                        }

                        if let responseString = String(data: messageData, encoding: .utf8) {
                            print("DEBUG: Received response: \(responseString.debugDescription)")
                            continuation.resume(returning: responseString)
                        } else {
                            continuation.resume(throwing: OnkyoClientError.invalidResponse)
                        }
                    }
                }
            }
        }

        // Send command and read responses
        return try await withCheckedThrowingContinuation { continuation in
            let state = ResumedState()

            connection.stateUpdateHandler = { connectionState in
                switch connectionState {
                case .ready:
                    // Connection established, send the packet
                    connection.send(content: packet, completion: .contentProcessed { error in
                        if error != nil {
                            if !state.checkAndSet() {
                                connection.cancel()
                                continuation.resume(throwing: OnkyoClientError.connectionFailed)
                            }
                        } else {
                            // Command sent, read up to 5 responses
                            Task {
                                print("DEBUG: Starting response loop, looking for '\(expectingPrefix)'")
                                do {
                                    for i in 1...5 {
                                        print("DEBUG: Loop iteration #\(i)")
                                        print("DEBUG: Calling readOneResponse()...")
                                        if let response = try await readOneResponse() {
                                            print("DEBUG: Got response in iteration #\(i)")
                                            if expectingPrefix.isEmpty || response.contains(expectingPrefix) {
                                                print("DEBUG: Response matches! Returning.")
                                                connection.cancel()
                                                if !state.checkAndSet() {
                                                    continuation.resume(returning: response)
                                                }
                                                return
                                            } else {
                                                print("DEBUG: Response #\(i) doesn't match '\(expectingPrefix)', continuing loop...")
                                            }
                                        }
                                    }
                                    print("DEBUG: Completed all \(5) iterations without finding match")
                                    // No matching response found
                                    connection.cancel()
                                    if !state.checkAndSet() {
                                        continuation.resume(throwing: OnkyoClientError.invalidResponse)
                                    }
                                } catch {
                                    connection.cancel()
                                    if !state.checkAndSet() {
                                        continuation.resume(throwing: error)
                                    }
                                }
                            }
                        }
                    })

                case .failed(_):
                    connection.cancel()
                    if !state.checkAndSet() {
                        continuation.resume(throwing: OnkyoClientError.connectionFailed)
                    }

                case .waiting(_):
                    connection.cancel()
                    if !state.checkAndSet() {
                        continuation.resume(throwing: OnkyoClientError.connectionFailed)
                    }

                default:
                    break
                }
            }

            // Start the connection
            connection.start(queue: queue)

            // Set up timeout
            queue.asyncAfter(deadline: .now() + Self.connectionTimeout) {
                if !state.checkAndSet() {
                    connection.cancel()
                    continuation.resume(throwing: OnkyoClientError.timeout)
                }
            }
        }
    }

    /// Builds an eISCP packet for the given command
    /// - Parameter command: The command string (e.g., "MVLUP")
    /// - Returns: The complete eISCP packet as Data
    private func buildPacket(for command: String) -> Data {
        var packet = Data()

        // Message format: "!1{command}\r\n"
        let message = "!1\(command)\r\n"
        let messageData = message.data(using: .utf8)!

        // Calculate sizes
        let dataSize = UInt32(messageData.count)
        let headerSize: UInt32 = 16

        // Header: "ISCP" (4 bytes)
        packet.append(contentsOf: "ISCP".utf8)

        // Header size: 16 (4 bytes, big-endian)
        packet.append(contentsOf: headerSize.bigEndian.bytes)

        // Data size: message length (4 bytes, big-endian)
        packet.append(contentsOf: dataSize.bigEndian.bytes)

        // Version: 0x01 (1 byte)
        packet.append(0x01)

        // Reserved: 0x00 (3 bytes)
        packet.append(contentsOf: [0x00, 0x00, 0x00])

        // Message
        packet.append(messageData)

        return packet
    }
}

// MARK: - Extensions

extension UInt32 {
    /// Converts UInt32 to big-endian byte array
    var bytes: [UInt8] {
        return [
            UInt8((self >> 24) & 0xFF),
            UInt8((self >> 16) & 0xFF),
            UInt8((self >> 8) & 0xFF),
            UInt8(self & 0xFF)
        ]
    }
}
