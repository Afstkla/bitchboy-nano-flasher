// ===================================================================================
// Project:   BitchBoy Nano - 2-key HID keypad for CH551, CH552, CH554
// License:   http://creativecommons.org/licenses/by-sa/3.0/
// ===================================================================================
//
// Turns a cheap CH552-based 2-key macropad into a plain USB HID keyboard. What each
// key sends, and how its LED behaves, is *data*: the flasher patches a blob into the
// compiled image rather than regenerating a header, so the app needs no C compiler.
//
// Blob layout, little-endian, all offsets from the start of KEYMAP:
//
//   0..7    magic "BBNKMAP" + format version
//   8..15   key 1 LED:  mode, green, blue, period_lo, period_hi, press, pressG, pressB
//   16..23  key 2 LED:  same
//   24..25  offset of key 2's action
//   26..    key 1's action, then key 2's action
//
// An action is a mode byte plus its payload:
//
//   0 hold kbd   mods, keycode          held down for as long as the key is
//   1 hold con   code_lo, code_hi       ditto, for a consumer/media key
//   2 sequence   count, then steps      run once per press
//
// A step is a kind byte plus its payload:
//
//   0 tap        mods, keycode
//   1 tap con    code_lo, code_hi
//   2 text       length, bytes
//   3 wait       ms_lo, ms_hi
//
// Entering the bootloader: hold both keys while plugging in (or, from stock
// firmware, pull UDP to 3.3V through 10k while plugging in - see README).

#include <stdint.h>

#include "config.h"
#include "system.h"
#include "delay.h"
#include "gpio.h"
#include "usb_conkbd.h"

void USB_interrupt(void);
void USB_ISR(void) __interrupt(INT_NO_USB) {
  USB_interrupt();
}

#define BLOB_SIZE     512
#define LED_AT(key)   (8 + 8 * (key))
#define KEY2_ACTION   24
#define KEY1_ACTION   26

#define ACT_HOLD_KBD  0
#define ACT_HOLD_CON  1
#define ACT_SEQUENCE  2

#define STEP_TAP      0
#define STEP_TAP_CON  1
#define STEP_TEXT     2
#define STEP_WAIT     3

// The flasher finds this by its magic and overwrites it. Unpatched, every action is
// mode 0 with keycode 0, which does nothing.
__code const uint8_t KEYMAP[BLOB_SIZE] = { 'B', 'B', 'N', 'K', 'M', 'A', 'P', 1 };

__code const uint8_t MOD_KEYS[4] = {
  KBD_KEY_LEFT_CTRL, KBD_KEY_LEFT_ALT, KBD_KEY_LEFT_SHIFT, KBD_KEY_LEFT_GUI
};

static uint8_t ledMode[2], ledG[2], ledB[2], ledPress[2], ledPressG[2], ledPressB[2];
static uint16_t ledStep[2], ledAccum[2];
static uint8_t phase[2], green[2], blue[2];

static uint16_t word_at(uint16_t at) {
  return (uint16_t)KEYMAP[at] | ((uint16_t)KEYMAP[at + 1] << 8);
}

static void LED_init(void) {
  PIN_low(KEY1_LED_ANODE);   PIN_output(KEY1_LED_ANODE);
  PIN_low(KEY2_LED_ANODE);   PIN_output(KEY2_LED_ANODE);
  PIN_high(KEY1_LED_GREEN);  PIN_output(KEY1_LED_GREEN);
  PIN_high(KEY1_LED_BLUE);   PIN_output(KEY1_LED_BLUE);
  PIN_high(KEY2_LED_GREEN);  PIN_output(KEY2_LED_GREEN);
  PIN_high(KEY2_LED_BLUE);   PIN_output(KEY2_LED_BLUE);
}

// Animation runs off an 8-bit phase rather than the millisecond count directly, so a
// period only costs a division once at startup instead of every frame.
static void LED_load(uint8_t key) {
  uint16_t at = LED_AT(key);
  uint16_t period = word_at(at + 3);
  ledMode[key]   = KEYMAP[at];
  ledG[key]      = KEYMAP[at + 1];
  ledB[key]      = KEYMAP[at + 2];
  ledStep[key]   = period < 256 ? 1 : period >> 8;
  ledPress[key]  = KEYMAP[at + 5];
  ledPressG[key] = KEYMAP[at + 6];
  ledPressB[key] = KEYMAP[at + 7];
}

static uint8_t triangle(uint8_t p) {
  return p < 128 ? (p << 1) : ((255 - p) << 1);
}

static uint8_t scale(uint8_t value, uint8_t by) {
  return (uint8_t)(((uint16_t)value * by) >> 8);
}

static void mix(uint8_t key) {
  uint8_t wave;
  switch(ledMode[key]) {
    case LED_MODE_SOLID:
      green[key] = ledG[key]; blue[key] = ledB[key];
      break;
    case LED_MODE_BREATHE:
      wave = triangle(phase[key]);
      green[key] = scale(ledG[key], wave); blue[key] = scale(ledB[key], wave);
      break;
    case LED_MODE_CYCLE:
      wave = triangle(phase[key]);
      green[key] = 255 - wave; blue[key] = wave;
      break;
    default:
      green[key] = 0; blue[key] = 0;
      break;
  }
  green[key] = scale(green[key], LED_BRIGHTNESS);
  blue[key]  = scale(blue[key], LED_BRIGHTNESS);
}

// One software-PWM period, roughly a millisecond. Cathodes sink, so a channel is lit
// while its line is held low. Both anodes are driven together; a key whose colour is
// fully off gets its anode dropped so nothing leaks through.
static void LED_render(void) {
  uint8_t step;
  uint8_t g1 = green[0] >> 3, b1 = blue[0] >> 3;
  uint8_t g2 = green[1] >> 3, b2 = blue[1] >> 3;

  PIN_write(KEY1_LED_ANODE, (green[0] | blue[0]) != 0);
  PIN_write(KEY2_LED_ANODE, (green[1] | blue[1]) != 0);

  for(step = 0; step < 32; step++) {
    PIN_write(KEY1_LED_GREEN, step >= g1);
    PIN_write(KEY1_LED_BLUE,  step >= b1);
    PIN_write(KEY2_LED_GREEN, step >= g2);
    PIN_write(KEY2_LED_BLUE,  step >= b2);
    DLY_us(20);
  }

  PIN_high(KEY1_LED_GREEN); PIN_high(KEY1_LED_BLUE);
  PIN_high(KEY2_LED_GREEN); PIN_high(KEY2_LED_BLUE);
}

static void pressMods(uint8_t mask) {
  uint8_t i;
  for(i = 0; i < 4; i++) if(mask & (1 << i)) KBD_press(MOD_KEYS[i]);
}

static void releaseMods(uint8_t mask) {
  uint8_t i = 4;
  while(i--) if(mask & (1 << i)) KBD_release(MOD_KEYS[i]);
}

static void runSequence(uint16_t at) {
  uint8_t left = KEYMAP[at + 1];
  uint16_t p = at + 2;
  uint8_t kind, mask, code, n, i;

  while(left--) {
    kind = KEYMAP[p++];
    if(kind == STEP_TAP) {
      mask = KEYMAP[p++];
      code = KEYMAP[p++];
      pressMods(mask);
      if(code) KBD_type(code);
      releaseMods(mask);
    } else if(kind == STEP_TAP_CON) {
      CON_type(word_at(p));
      p += 2;
    } else if(kind == STEP_TEXT) {
      n = KEYMAP[p++];
      for(i = 0; i < n; i++) KBD_type(KEYMAP[p + i]);
      p += n;
    } else {
      DLY_ms(word_at(p));
      p += 2;
    }
  }
}

static void action(uint16_t at, __bit down) {
  uint8_t mode = KEYMAP[at];
  uint8_t mask, code;

  if(mode == ACT_HOLD_KBD) {
    mask = KEYMAP[at + 1];
    code = KEYMAP[at + 2];
    if(down) {
      pressMods(mask);
      if(code) KBD_press(code);
    } else {
      if(code) KBD_release(code);
      releaseMods(mask);
    }
  } else if(mode == ACT_HOLD_CON) {
    if(down) CON_press(word_at(at + 1)); else CON_release(word_at(at + 1));
  } else if(down) {
    runSequence(at);
  }
}

void main(void) {
  __bit key1 = 0, key2 = 0, now;
  uint16_t action1 = KEY1_ACTION, action2;

  CLK_config();
  DLY_ms(5);

  PIN_input_PU(KEY1_PIN);
  PIN_input_PU(KEY2_PIN);
  DLY_ms(1);

  // Both keys held while plugging in -> jump straight to the bootloader.
  if(!PIN_read(KEY1_PIN) && !PIN_read(KEY2_PIN)) BOOT_now();

  action2 = word_at(KEY2_ACTION);
  LED_load(0);
  LED_load(1);

  KBD_init();
  LED_init();
  DLY_ms(10);

  while(1) {
    now = !PIN_read(KEY1_PIN);
    if(now != key1) {
      key1 = now;
      action(action1, now);
      DLY_ms(KEY_DEBOUNCE_MS);
    }

    now = !PIN_read(KEY2_PIN);
    if(now != key2) {
      key2 = now;
      action(action2, now);
      DLY_ms(KEY_DEBOUNCE_MS);
    }

    if(++ledAccum[0] >= ledStep[0]) { ledAccum[0] = 0; phase[0]++; }
    if(++ledAccum[1] >= ledStep[1]) { ledAccum[1] = 0; phase[1]++; }

    if(key1 && ledPress[0]) {
      green[0] = scale(ledPressG[0], LED_BRIGHTNESS);
      blue[0]  = scale(ledPressB[0], LED_BRIGHTNESS);
    } else {
      mix(0);
    }

    if(key2 && ledPress[1]) {
      green[1] = scale(ledPressG[1], LED_BRIGHTNESS);
      blue[1]  = scale(ledPressB[1], LED_BRIGHTNESS);
    } else {
      mix(1);
    }

    LED_render();
  }
}
