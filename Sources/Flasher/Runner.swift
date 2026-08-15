import Foundation

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // Flasher/
    .deletingLastPathComponent()   // Sources/
    .deletingLastPathComponent()   // repo root
let firmwareDir = repoRoot.appendingPathComponent("firmware")
let specsFile = firmwareDir.appendingPathComponent("keymap.json")

final class Runner: ObservableObject {
    @Published var log = ""
    @Published var running = false

    private var current: Process?
    private var cancelled = false

    func flash(_ spec1: KeySpec, _ spec2: KeySpec) {
        let keymap: String
        do {
            keymap = try keymapFile(spec1, spec2)
        } catch {
            append("ERROR: \(error.localizedDescription)\n")
            return
        }
        running = true
        cancelled = false
        log = ""
        DispatchQueue.global().async { [self] in
            do {
                try keymap.write(to: firmwareDir.appendingPathComponent("keymap.h"),
                                 atomically: true, encoding: .utf8)
                try saveSpecs([spec1, spec2], to: specsFile)
                append("Wrote firmware/keymap.h, compiling ...\n")
                try run(["make", "-C", firmwareDir.path, "bin"],
                        hint: "make/sdcc not found - run: brew install sdcc")
                append("\n")
                try run(["uv", "run", "flash.py"],
                        hint: "uv not found - install it from https://docs.astral.sh/uv/")
                append("\nDone! Replug the pad and it comes up with the new keymap.\n")
            } catch {
                append(cancelled ? "\nCancelled.\n" : "\nFAILED: \(error.localizedDescription)\n")
            }
            DispatchQueue.main.async { self.running = false }
        }
    }

    func cancel() {
        cancelled = true
        current?.terminate()
    }

    private func run(_ cmd: [String], hint: String) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = cmd
        proc.currentDirectoryURL = repoRoot

        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        env["PATH"] = "\(env["PATH"] ?? ""):/opt/homebrew/bin:/usr/local/bin:\(home)/.local/bin"
        env["PYTHONUNBUFFERED"] = "1"
        proc.environment = env

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                self?.append(text)
            }
        }

        current = proc
        do {
            try proc.run()
        } catch {
            throw KeymapError(message: hint)
        }
        proc.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil
        current = nil
        if proc.terminationStatus != 0 {
            throw KeymapError(message: "\(cmd[0]) exited \(proc.terminationStatus)")
        }
    }

    private func append(_ text: String) {
        DispatchQueue.main.async { self.log += text }
    }
}
