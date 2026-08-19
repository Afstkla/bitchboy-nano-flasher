import Foundation

private let checkoutRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // Flasher/
    .deletingLastPathComponent()   // Sources/
    .deletingLastPathComponent()   // repo root

// Set when running from a .app rather than `swift run`.
private let bundledRoot: URL? = {
    guard let res = Bundle.main.resourceURL,
          FileManager.default.fileExists(
            atPath: res.appendingPathComponent("firmware/keypad.bin").path)
    else { return nil }
    return res
}()

private let appSupport = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("BitchBoy Nano")

// The base image is only ever read, so it can live inside a signed bundle; only the
// remembered keymap needs somewhere writable.
let firmwareImage = (bundledRoot ?? checkoutRoot)
    .appendingPathComponent("firmware/keypad.bin")
let specsFile = bundledRoot == nil
    ? checkoutRoot.appendingPathComponent("firmware/keymap.json")
    : appSupport.appendingPathComponent("keymap.json")

private let bootloaderTimeout = 120.0

final class Runner: ObservableObject {
    @Published var log = ""
    @Published var running = false

    private var cancelled = false

    func flash(_ spec1: KeySpec, _ spec2: KeySpec) {
        let image: [UInt8]
        do {
            let base = try Data(contentsOf: firmwareImage)
            image = try patchedFirmware([UInt8](base),
                                        with: try keymapBlob(spec1, spec2))
        } catch {
            append("ERROR: \(error.localizedDescription)\n")
            return
        }
        running = true
        cancelled = false
        log = ""
        DispatchQueue.global().async { [self] in
            do {
                try? FileManager.default.createDirectory(
                    at: specsFile.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                try saveSpecs([spec1, spec2], to: specsFile)

                append("""
                Put the pad in bootloader mode:
                  * running this firmware already: unplug, HOLD BOTH BUTTONS, replug
                  * stock firmware: bridge pin 12 (UDP) to pin 16 (V33) through 10k
                    while plugging in, then remove the resistor
                Waiting for the bootloader ...

                """)
                append("Patched \(image.count) bytes from \(firmwareImage.path)\n\n")
                try waitForBootloader()
                try CH55x(log: { append($0) }).program(image) { append($0) }
                append("\nDone! The pad restarts with the new keymap.\n")
            } catch {
                append(cancelled ? "\nCancelled.\n"
                                 : "\nFAILED: \(error.localizedDescription)\n")
            }
            DispatchQueue.main.async { self.running = false }
        }
    }

    func cancel() { cancelled = true }

    private func waitForBootloader() throws {
        let deadline = Date().addingTimeInterval(bootloaderTimeout)
        while !bootloaderAttached() {
            if cancelled { throw KeymapError(message: "cancelled") }
            guard Date() < deadline else {
                throw KeymapError(message:
                    "timed out waiting for the bootloader - nothing was flashed")
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        // The interface nub is published a moment after the device attaches.
        Thread.sleep(forTimeInterval: 0.3)
    }

    // Mirrored to stdout so a run started from a terminal leaves a log behind.
    private func append(_ text: String) {
        print(text, terminator: "")
        DispatchQueue.main.async { self.log += text }
    }
}
