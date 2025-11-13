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
    private static let connectionTimeout: TimeInterval = 5.0

    // MARK: - Commands

    enum Command: String {
        case volumeUp = "MVLUP"
        case volumeDown = "MVLDOWN"
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

    // MARK: - Private Methods

    /// Sends a raw eISCP command string
    private func sendRawCommand(_ command: String, to host: String) async throws {
        // Build the eISCP packet
        let packet = buildPacket(for: command)

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
            connection.start(queue: .global())

            // Set up timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.connectionTimeout) {
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
