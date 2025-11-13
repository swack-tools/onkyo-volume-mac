#!/usr/bin/env swift

import Foundation
import Network

// Simple eISCP test tool
class EISCPTester {
    let host: String
    let port: UInt16 = 60128

    init(host: String) {
        self.host = host
    }

    func buildPacket(for command: String) -> Data {
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
        packet.append(contentsOf: [
            UInt8((headerSize >> 24) & 0xFF),
            UInt8((headerSize >> 16) & 0xFF),
            UInt8((headerSize >> 8) & 0xFF),
            UInt8(headerSize & 0xFF)
        ])

        // Data size: message length (4 bytes, big-endian)
        packet.append(contentsOf: [
            UInt8((dataSize >> 24) & 0xFF),
            UInt8((dataSize >> 16) & 0xFF),
            UInt8((dataSize >> 8) & 0xFF),
            UInt8(dataSize & 0xFF)
        ])

        // Version: 0x01 (1 byte)
        packet.append(0x01)

        // Reserved: 0x00 (3 bytes)
        packet.append(contentsOf: [0x00, 0x00, 0x00])

        // Message
        packet.append(messageData)

        return packet
    }

    func testCommand(_ command: String) {
        print("================================================================================")
        print("Testing command: \(command)")
        print("Connecting to \(host):\(port)...")

        let packet = buildPacket(for: command)
        print("Sending packet (\(packet.count) bytes):")
        print("  Header: \(packet[0..<4].map { String(format: "%02X", $0) }.joined(separator: " "))")
        print("  Message: \(String(data: packet[16...], encoding: .utf8) ?? "N/A")")

        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: port),
            using: .tcp
        )

        let semaphore = DispatchSemaphore(value: 0)
        var responseCount = 0

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("✓ Connected!")

                // Send command
                connection.send(content: packet, completion: .contentProcessed { error in
                    if let error = error {
                        print("✗ Send error: \(error)")
                        connection.cancel()
                        semaphore.signal()
                    } else {
                        print("✓ Command sent, reading responses...")

                        // Read responses
                        func readNextResponse() {
                            responseCount += 1
                            if responseCount > 5 {
                                print("⚠ Max 5 responses reached, stopping")
                                connection.cancel()
                                semaphore.signal()
                                return
                            }

                            connection.receive(minimumIncompleteLength: 16, maximumLength: 16) { headerData, _, _, headerError in
                                guard headerError == nil, let headerData = headerData, headerData.count == 16 else {
                                    print("✗ Header read error: \(headerError?.localizedDescription ?? "unknown")")
                                    connection.cancel()
                                    semaphore.signal()
                                    return
                                }

                                // Parse data size
                                let dataSizeBytes = headerData[8..<12]
                                let dataSize = dataSizeBytes.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

                                print("\n--- Response #\(responseCount) ---")
                                print("  Header: \(headerData.map { String(format: "%02X", $0) }.joined(separator: " "))")
                                print("  Data size: \(dataSize) bytes")

                                // Read message
                                connection.receive(minimumIncompleteLength: Int(dataSize), maximumLength: Int(dataSize)) { messageData, _, _, messageError in
                                    guard messageError == nil, let messageData = messageData else {
                                        print("✗ Message read error: \(messageError?.localizedDescription ?? "unknown")")
                                        connection.cancel()
                                        semaphore.signal()
                                        return
                                    }

                                    if let responseString = String(data: messageData, encoding: .utf8) {
                                        print("  Message (string): \(responseString.debugDescription)")
                                        print("  Message (hex): \(messageData.map { String(format: "%02X", $0) }.joined(separator: " "))")

                                        // Check if this is what we want
                                        if responseString.contains("MVL") {
                                            print("  ✓ Found MVL response!")
                                            connection.cancel()
                                            semaphore.signal()
                                        } else {
                                            print("  ℹ Not a MVL response, reading next...")
                                            readNextResponse()
                                        }
                                    } else {
                                        print("✗ Could not decode message as UTF-8")
                                        connection.cancel()
                                        semaphore.signal()
                                    }
                                }
                            }
                        }

                        readNextResponse()
                    }
                })

            case .failed(let error):
                print("✗ Connection failed: \(error)")
                semaphore.signal()

            case .waiting(let error):
                print("⚠ Connection waiting: \(error)")

            default:
                break
            }
        }

        connection.start(queue: .global())

        // Wait max 10 seconds
        let timeout = DispatchTime.now() + .seconds(10)
        if semaphore.wait(timeout: timeout) == .timedOut {
            print("✗ Timeout after 10 seconds")
            connection.cancel()
        }

        print("")
    }
}

// Main
if CommandLine.arguments.count < 2 {
    print("Usage: swift test-eiscp.swift <receiver-ip>")
    print("Example: swift test-eiscp.swift 192.168.1.100")
    exit(1)
}

let receiverIP = CommandLine.arguments[1]
let tester = EISCPTester(host: receiverIP)

print("eISCP Protocol Tester")
print("================================================================================")
print("Testing Onkyo receiver at: \(receiverIP)")
print("")

// Test volume up
tester.testCommand("MVLUP")

// Wait a bit
sleep(1)

// Test volume query
tester.testCommand("MVLQSTN")

// Wait a bit
sleep(1)

// Test setting volume to 30 (hex 1E)
tester.testCommand("MVL1E")

print("================================================================================")
print("Testing complete!")
