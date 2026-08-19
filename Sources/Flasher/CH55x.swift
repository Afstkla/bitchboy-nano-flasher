import Foundation
import IOKit
import IOUSBHost

// A Swift port of the flashing half of chprog.py (Stefan Wagner, MIT), talking to the
// CH55x mask-ROM bootloader over IOKit so the app needs no Python and no libusb.
//
// ponytail: bootloader v2 only. Every "曾大大" pad is a CH552 with a 2.x bootloader,
// and chprog's v1 path is dead code that does not even run (it calls __sendcmd
// unbound). A v1 chip is detected and reported rather than half-flashed.

let bootloaderVID = 0x4348
let bootloaderPID = 0x55E0

private let detectCommand: [UInt8] = [
    0xa1, 0x12, 0x00, 0x52, 0x11, 0x4d, 0x43, 0x55, 0x20, 0x49, 0x53, 0x50,
    0x20, 0x26, 0x20, 0x57, 0x43, 0x48, 0x2e, 0x43, 0x4e,
]
private let writeMode: UInt8 = 0xa5
private let verifyMode: UInt8 = 0xa6

private func findService(_ className: String) -> io_service_t {
    let matching = IOServiceMatching(className) as NSMutableDictionary
    matching["idVendor"] = bootloaderVID
    matching["idProduct"] = bootloaderPID
    return IOServiceGetMatchingService(kIOMainPortDefault, matching as CFDictionary)
}

// The interface nub is a child of the device in the service plane. Finding it there
// rather than by another property match ties it to *this* device, and sidesteps how
// long IOKit takes to publish it for matching.
private func interfaceChild(of device: io_service_t) -> io_service_t {
    var children: io_iterator_t = 0
    guard IORegistryEntryGetChildIterator(device, kIOServicePlane, &children) == KERN_SUCCESS
    else { return 0 }
    defer { IOObjectRelease(children) }
    while case let child = IOIteratorNext(children), child != 0 {
        if IOObjectConformsTo(child, "IOUSBHostInterface") != 0 { return child }
        IOObjectRelease(child)
    }
    return 0
}

func bootloaderAttached() -> Bool {
    let service = findService("IOUSBHostDevice")
    guard service != 0 else { return false }
    IOObjectRelease(service)
    return true
}

final class CH55x {
    private let device: IOUSBHostDevice
    private let interface: IOUSBHostInterface
    private let inPipe: IOUSBHostPipe
    private let outPipe: IOUSBHostPipe

    private var chipID: UInt8 = 0
    private(set) var chipName = "CH55x"
    private(set) var bootloaderVersion = "?"
    private var codeFlashSize = 14336

    init(log: (String) -> Void = { _ in }) throws {
        let deviceService = findService("IOUSBHostDevice")
        guard deviceService != 0 else {
            throw KeymapError(message: "no CH55x bootloader on the bus")
        }
        defer { IOObjectRelease(deviceService) }
        do {
            device = try IOUSBHostDevice(__ioService: deviceService, options: [],
                                         queue: nil, interestHandler: nil)
        } catch {
            throw KeymapError(message: "could not open the bootloader: "
                              + error.localizedDescription)
        }
        log("Opened the bootloader device.\n")

        // Nothing in macOS drives a vendor-specific device, so it is left unconfigured
        // and publishes no interface until we select a configuration ourselves.
        var interfaceService = interfaceChild(of: deviceService)
        if interfaceService == 0 {
            do {
                try device.__configure(withValue: 1, matchInterfaces: true)
            } catch {
                device.destroy()
                throw KeymapError(message: "could not configure the bootloader: "
                                  + error.localizedDescription)
            }
            let deadline = Date().addingTimeInterval(5)
            var waited = 0
            while interfaceService == 0 && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
                waited += 1
                interfaceService = interfaceChild(of: deviceService)
            }
            log("Configured; interface appeared after \(waited * 50) ms.\n")
        }
        guard interfaceService != 0 else {
            device.destroy()
            throw KeymapError(message: "the bootloader published no USB interface")
        }
        defer { IOObjectRelease(interfaceService) }

        do {
            interface = try IOUSBHostInterface(__ioService: interfaceService, options: [],
                                               queue: nil, interestHandler: nil)
            // ponytail: the CH55x bootloader's bulk pair is always 0x02/0x82 - every
            // other implementation hardcodes it too. Walk the endpoint descriptors if
            // a pad ever shows up that doesn't.
            outPipe = try interface.copyPipe(withAddress: 0x02)
            inPipe = try interface.copyPipe(withAddress: 0x82)
        } catch {
            device.destroy()
            throw KeymapError(message: "could not claim the bootloader interface: "
                              + error.localizedDescription)
        }
    }

    deinit {
        interface.destroy()
        device.destroy()
    }

    func program(_ image: [UInt8], log: (String) -> Void) throws {
        try identify()
        log("Found \(chipName), bootloader v\(bootloaderVersion).\n")
        guard image.count <= codeFlashSize else {
            throw KeymapError(message: "firmware is \(image.count) bytes, "
                              + "\(chipName) holds \(codeFlashSize)")
        }
        log("Erasing ...\n")
        try erase()
        log("Writing \(image.count) bytes ...\n")
        try transfer(image, mode: writeMode, what: "write")
        log("Verifying ...\n")
        try transfer(image, mode: verifyMode, what: "verify")
        try send([0xa2, 0x01, 0x00, 0x01])          // leave the bootloader, run the app
        log("Done.\n")
    }

    private func identify() throws {
        let ident = try command(detectCommand)
        guard ident.count == 6 else {
            throw KeymapError(message: ident.count == 2
                ? "this chip has a v1 bootloader, which this flasher does not speak"
                : "chip identification failed")
        }
        chipID = ident[4]
        chipName = "CH5\(Int(chipID) - 30)"
        if chipID == 0x51 || chipID == 0x53 { codeFlashSize = 10240 }

        let config = try command([0xa7, 0x02, 0x00, 0x1f, 0x00])
        guard config.count == 30 else {
            throw KeymapError(message: "unexpected bootloader config reply")
        }
        bootloaderVersion = "\(config[19]).\(config[20])\(config[21])"

        // The bootloader XORs flash payloads with a key derived from its unique ID.
        var key = [UInt8](repeating: 0, count: 64)
        key[0] = 0xa3
        key[1] = 0x30
        let sum = UInt8(truncatingIfNeeded:
            Int(config[22]) + Int(config[23]) + Int(config[24]) + Int(config[25]))
        for i in 0..<0x30 { key[i + 3] = sum }
        try command(key)
    }

    private func erase() throws {
        let reply = try command([0xa4, 0x01, 0x00, 8])
        guard reply.count > 4, reply[4] == 0 else {
            throw KeymapError(message: "erase failed")
        }
    }

    private func transfer(_ image: [UInt8], mode: UInt8, what: String) throws {
        var address = 0
        while address < image.count {
            let chunk = min(0x38, image.count - address)
            var packet = [UInt8](repeating: 0, count: 64)
            packet[0] = mode
            packet[1] = UInt8(chunk + 5)
            packet[3] = UInt8(address & 0xff)
            packet[4] = UInt8((address >> 8) & 0xff)
            packet[7] = UInt8((image.count - address) & 0xff)
            for i in 0..<chunk { packet[i + 8] = image[address + i] }
            for i in stride(from: 7, to: chunk + 8, by: 8) { packet[i] ^= chipID }

            let reply = try command(packet)
            guard reply.count > 4,
                  reply[4] == 0 || reply[4] == 0xfe || reply[4] == 0xf5 else {
                throw KeymapError(message: String(format: "%@ failed at 0x%04x",
                                                  what, address))
            }
            address += chunk
        }
    }

    @discardableResult
    private func command(_ bytes: [UInt8]) throws -> [UInt8] {
        try send(bytes)
        let buffer = NSMutableData(length: 64)!
        var moved = 0
        try inPipe.__sendIORequest(with: buffer, bytesTransferred: &moved,
                                   completionTimeout: 5)
        return [UInt8](Data(bytes: buffer.bytes, count: moved))
    }

    private func send(_ bytes: [UInt8]) throws {
        let data = NSMutableData(bytes: bytes, length: bytes.count)
        var moved = 0
        try outPipe.__sendIORequest(with: data, bytesTransferred: &moved,
                                    completionTimeout: 5)
        guard moved == bytes.count else {
            throw KeymapError(message: "short write to the bootloader")
        }
    }
}
