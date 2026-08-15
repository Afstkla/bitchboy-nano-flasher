// ===================================================================================
// User Configuration - BitchBoy Nano (CH552 2-key HID keypad)
// ===================================================================================

#pragma once

// Key wiring, discovered on the "曾大大" 2-key pad (see 2button-pad-hack README).
// Valid pin names: P11, P14, P15, P16, P17, P30, P31, P32, P33, P34
#define KEY1_PIN        P32     // left key
#define KEY2_PIN        P14     // right key

#define KEY_DEBOUNCE_MS 12      // lockout after an edge, in milliseconds

// Per-key RGB LEDs, common anode, discovered by sweeping every pin pair - the red die
// is not wired to anything on this board, so green and blue are all there is. None of
// these share a pin with a switch, so the LEDs need no multiplexing against key scans.
#define KEY1_LED_ANODE  P17
#define KEY1_LED_GREEN  P30
#define KEY1_LED_BLUE   P31

#define KEY2_LED_ANODE  P11
#define KEY2_LED_GREEN  P34
#define KEY2_LED_BLUE   P33

// Global ceiling on LED duty, 0..255. The board's series resistors are unknown, so
// this is the knob to back off if the LEDs ever run hot or too bright.
#define LED_BRIGHTNESS  255

#define LED_MODE_OFF      0
#define LED_MODE_SOLID    1
#define LED_MODE_BREATHE  2
#define LED_MODE_CYCLE    3

// USB device descriptor. 0x1209/0x0001 is the pid.codes "interim / private
// testing" ID - fine for a personal one-off.
#define USB_VENDOR_ID       0x1209
#define USB_PRODUCT_ID      0x0001
#define USB_DEVICE_VERSION  0x0100
#define USB_MAX_POWER_mA    50

#define MANUFACTURER_STR    'D','I','Y'
#define PRODUCT_STR         'B','i','t','c','h','B','o','y',' ','N','a','n','o'
#define SERIAL_STR          'C','H','5','5','2'
#define INTERFACE_STR       'H','I','D','-','K','e','y','b','o','a','r','d'
