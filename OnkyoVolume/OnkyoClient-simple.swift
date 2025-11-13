//
//  OnkyoClient-simple.swift
//  Simplified version using exact CLI test pattern
//

import Foundation
import Network

class OnkyoClientSimple {
    private static let defaultPort: UInt16 = 60128
    private static let connectionTimeout: TimeInterval = 3.0 // Shorter timeout for GUI responsiveness

    func queryVolume(from host: String) async throws -> Int {
        let response = try await sendCommand("MVLQSTN", to: host, expectingPrefix: "MVL")

        // Parse MVL response - format is "!1MVL{hex}\u{1A}\r\n"
        // where {hex} is a 2-digit hex value (e.g., "29" = 0x29 = 41 decimal)
        let cleaned = response.replacingOccurrences(of: "!1", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\u{1A}", with: "") // Remove EOF character
            .trimmingCharacters(in: .whitespaces)

        if cleaned.hasPrefix("MVL") {
            // Extract just the hex digits after MVL (e.g., "MVL29" -> "29")
            let hexString = String(cleaned.dropFirst(3)).filter { $0.isHexDigit }
            if let hexValue = Int(hexString, radix: 16) {
                // Return hex value as-is (maps 1:1 to receiver display)
                return hexValue
            }
        }
        throw NSError(domain: "OnkyoClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
    }

    func setVolume(_ volume: Int, to host: String) async throws {
        let hexValue = String(format: "%02X", max(0, min(100, volume)))
        _ = try await sendCommand("MVL\(hexValue)", to: host, expectingPrefix: "MVL")
    }

    func volumeUp(to host: String) async throws {
        _ = try await sendCommand("MVLUP", to: host, expectingPrefix: "MVL")
    }

    func volumeDown(to host: String) async throws {
        _ = try await sendCommand("MVLDOWN", to: host, expectingPrefix: "MVL")
    }

    func setMute(_ muted: Bool, to host: String) async throws {
        let command = muted ? "AMT01" : "AMT00"
        _ = try await sendCommand(command, to: host, expectingPrefix: "AMT")
    }

    private func sendCommand(_ command: String, to host: String, expectingPrefix: String) async throws -> String {
        let packet = buildPacket(for: command)

        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            let queue = DispatchQueue(label: "onkyo.\(UUID().uuidString)")

            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(integerLiteral: Self.defaultPort),
                using: .tcp
            )

            // RECURSIVE read function - SAME as CLI test
            func readNextResponse() {
                // Read header
                connection.receive(minimumIncompleteLength: 16, maximumLength: 16) { headerData, _, _, headerError in
                    guard headerError == nil, let headerData = headerData, headerData.count == 16 else {
                        if !resumed {
                            resumed = true
                            connection.cancel()
                            continuation.resume(throwing: NSError(domain: "OnkyoClient", code: -1))
                        }
                        return
                    }

                    // Parse data size
                    let dataSize = headerData[8..<12].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

                    // Read message
                    connection.receive(minimumIncompleteLength: Int(dataSize), maximumLength: Int(dataSize)) { messageData, _, _, messageError in
                        guard messageError == nil, let messageData = messageData,
                              let responseString = String(data: messageData, encoding: .utf8) else {
                            if !resumed {
                                resumed = true
                                connection.cancel()
                                continuation.resume(throwing: NSError(domain: "OnkyoClient", code: -1))
                            }
                            return
                        }

                        // Check if this matches what we want
                        if responseString.contains(expectingPrefix) {
                            if !resumed {
                                resumed = true
                                connection.cancel()
                                continuation.resume(returning: responseString)
                            }
                        } else {
                            readNextResponse() // RECURSIVE CALL
                        }
                    }
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: packet, completion: .contentProcessed { error in
                        if error != nil {
                            if !resumed {
                                resumed = true
                                connection.cancel()
                                continuation.resume(throwing: NSError(domain: "OnkyoClient", code: -1))
                            }
                        } else {
                            readNextResponse() // Start reading
                        }
                    })
                case .failed(_), .waiting(_):
                    if !resumed {
                        resumed = true
                        connection.cancel()
                        continuation.resume(throwing: NSError(domain: "OnkyoClient", code: -1))
                    }
                default:
                    break
                }
            }

            connection.start(queue: queue)

            // Timeout
            queue.asyncAfter(deadline: .now() + Self.connectionTimeout) {
                if !resumed {
                    resumed = true
                    connection.cancel()
                    continuation.resume(throwing: NSError(domain: "OnkyoClient", code: -1))
                }
            }
        }
    }

    private func buildPacket(for command: String) -> Data {
        var packet = Data()
        let message = "!1\(command)\r\n"
        let messageData = message.data(using: .utf8)!
        let dataSize = UInt32(messageData.count)
        let headerSize: UInt32 = 16

        packet.append(contentsOf: "ISCP".utf8)
        packet.append(contentsOf: [
            UInt8((headerSize >> 24) & 0xFF), UInt8((headerSize >> 16) & 0xFF),
            UInt8((headerSize >> 8) & 0xFF), UInt8(headerSize & 0xFF)
        ])
        packet.append(contentsOf: [
            UInt8((dataSize >> 24) & 0xFF), UInt8((dataSize >> 16) & 0xFF),
            UInt8((dataSize >> 8) & 0xFF), UInt8(dataSize & 0xFF)
        ])
        packet.append(contentsOf: [0x01, 0x00, 0x00, 0x00])
        packet.append(messageData)

        return packet
    }
}
