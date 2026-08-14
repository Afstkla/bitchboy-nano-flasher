#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["pyusb"]
# ///
"""Poll for the CH55x bootloader and flash firmware/keypad.bin.

Headless companion to the SwiftUI flasher app; usable standalone via uv run flash.py.
"""

import os
import subprocess
import sys
import time

import usb.core

ROOT = os.path.dirname(os.path.abspath(__file__))
BIN = os.path.join(ROOT, "firmware", "keypad.bin")
CHPROG = os.path.join(ROOT, "chprog.py")

BOOT_VID, BOOT_PID = 0x4348, 0x55E0
TIMEOUT_S = 120


def main():
    if not os.path.exists(BIN):
        sys.exit(f"firmware not found: {BIN} - build it first")

    print("Put the pad in bootloader mode:")
    print("  * running this firmware already: unplug, HOLD BOTH BUTTONS, replug")
    print("  * stock firmware: bridge pin 12 (UDP) to pin 16 (V33) through 10k")
    print("    while plugging in, then remove the resistor")
    print(f"Waiting up to {TIMEOUT_S}s for bootloader ({BOOT_VID:04x}:{BOOT_PID:04x}) ...")

    deadline = time.time() + TIMEOUT_S
    while time.time() < deadline:
        try:
            dev = usb.core.find(idVendor=BOOT_VID, idProduct=BOOT_PID)
        except usb.core.NoBackendError:
            sys.exit("libusb missing - run: brew install libusb")
        if dev is not None:
            print("\nBootloader detected. Flashing ...")
            sys.exit(subprocess.run([sys.executable, CHPROG, BIN]).returncode)
        time.sleep(0.2)

    sys.exit("timed out, no bootloader appeared - nothing was flashed")


if __name__ == "__main__":
    main()
