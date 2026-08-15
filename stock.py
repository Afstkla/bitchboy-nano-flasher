#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["hidapi"]
# ///
"""Reconfigure the stock zdd pad over USB HID, without the bootloader.

Protocol reverse-engineered by TabbycatPie/CustomKeyboard, which reimplements the
vendor's Windows tool. The pad stores its keymap in DataFlash; this rewrites it.
No relation to the CH552 bootloader or the firmware in ./firmware.

  ./stock.py discover        slots 0-9 send 'a'-'j'; press a key, read the letter
  ./stock.py set 1=x 4=cmd+shift+4
"""

import sys

import hid

VID, PID = 0x5131, 0x2019
SLOTS = 10
ACK = bytes([0x55, 0x55, 0x55])

MODIFIERS = {"ctrl": 0x01, "shift": 0x02, "alt": 0x04, "opt": 0x04,
             "cmd": 0x08, "win": 0x08, "gui": 0x08}

NAMED = {"enter": 0x28, "esc": 0x29, "backspace": 0x2A, "tab": 0x2B, "space": 0x2C,
         "right": 0x4F, "left": 0x50, "down": 0x51, "up": 0x52}


def usage(name):
    if len(name) == 1 and name.isalpha():
        return 0x04 + ord(name) - ord("a")
    if name == "0":
        return 0x27
    if len(name) == 1 and name.isdigit():
        return 0x1E + int(name) - 1
    if name.startswith("f") and name[1:].isdigit() and 1 <= int(name[1:]) <= 12:
        return 0x3A + int(name[1:]) - 1
    if name in NAMED:
        return NAMED[name]
    raise SystemExit(f"unknown key: {name}")


def parse(combo):
    *mods, key = combo.lower().split("+")
    bits = 0
    for m in mods:
        if m not in MODIFIERS:
            raise SystemExit(f"unknown modifier: {m}")
        bits |= MODIFIERS[m]
    return bits, usage(key)


def frame(command, payload=()):
    body = bytes([0x00, command]) + bytes(payload)
    return body.ljust(65, b"\x00")


def open_config_interface():
    """The pad exposes several HID interfaces; only one answers the ACK probe."""
    for entry in hid.enumerate(VID, PID):
        try:
            device = hid.Device(path=entry["path"])
            device.write(frame(0x0C))
            if bytes(device.read(64, 500)[:3]) == ACK:
                return device
            device.close()
        except hid.HIDException:
            continue
    raise SystemExit(
        "pad not found on 5131:2019 — plugged in? Terminal may need Input Monitoring "
        "under System Settings > Privacy & Security."
    )


def download(keymap):
    """keymap: {slot: (modifier_bits, hid_usage)}. Unlisted slots are cleared."""
    normal = [keymap.get(s, (0, 0))[1] for s in range(SLOTS)]
    special = [keymap.get(s, (0, 0))[0] for s in range(SLOTS)]

    device = open_config_interface()
    for command, payload in [(0x01, normal), (0x02, special), (0x03, [0, 0]),
                             (0x04, []), (0x05, []), (0x06, []), (0x08, []),
                             (0x09, []), (0x0A, []), (0x0B, []), (0x07, [])]:
        device.write(frame(command, payload))
        if bytes(device.read(64, 500)[:3]) != ACK:
            raise SystemExit(f"no ACK for command 0x{command:02x}")
    device.close()


def check():
    assert frame(0x01, [0x1E, 0x1F])[:4] == b"\x00\x01\x1e\x1f"
    assert len(frame(0x01, range(10))) == 65
    assert parse("cmd+shift+4") == (0x0A, 0x21)
    assert parse("a") == (0, 0x04)
    assert parse("f5") == (0, 0x3E)
    print("ok")


def main():
    match sys.argv[1:]:
        case ["--check"]:
            check()
        case ["discover"]:
            download({slot: (0, 0x04 + slot) for slot in range(SLOTS)})
            print("slots 0-9 now send a-j; press each key to find its slot")
        case ["set", *assignments] if assignments:
            download({int(s): parse(c)
                      for s, c in (a.split("=", 1) for a in assignments)})
            print("written; unplug and replug to confirm it stuck")
        case _:
            raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
