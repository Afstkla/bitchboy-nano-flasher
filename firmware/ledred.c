// ===================================================================================
// BitchBoy Nano - hunting the red channel
// ===================================================================================
//
// Confirmed so far, two independent common-anode RGB LEDs:
//
//   right key   anode P1.1   green P3.4   blue P3.3   red ?
//   left  key   anode P1.7   green P3.0   blue P3.1   red ?
//
// Pairs both known anodes against every other pin, in both directions. Unlike the
// keyed sweeps this drives P1.4 and P3.2 as well, so the switch pins are finally
// covered - which means stepping has to be automatic rather than key driven.
//
// P1.5 and P1.6 come first: they are the only non-switch pins left unaccounted for,
// so structurally they are where red should be.
//
// Build with: make -C firmware SKETCH=ledred.c bin
//
// Both keys held while plugging in still jumps to the bootloader.

#include <stdint.h>

#include "config.h"
#include "system.h"
#include "delay.h"
#include "gpio.h"
#include "usb_conkbd.h"

#define ANCHOR_COUNT 2
#define OTHER_COUNT  10
#define DWELL_TICKS  20   // x 100ms

#define ON_MS   1
#define OFF_MS  3

void USB_interrupt(void);
void USB_ISR(void) __interrupt(INT_NO_USB) {
  USB_interrupt();
}

__code const uint8_t ANCHORS[ANCHOR_COUNT] = { P11, P17 };
__code const uint8_t OTHERS[OTHER_COUNT] = {
  P15, P16, P14, P32, P33, P34, P30, P31, P11, P17
};

static void pinInput(uint8_t pin) {
  if(pin < P30) { P1_DIR_PU &= ~(1 << pin); P1_MOD_OC &= ~(1 << pin); }
  else          { P3_DIR_PU &= ~(1 << (pin - P30)); P3_MOD_OC &= ~(1 << (pin - P30)); }
}

static void pinOutput(uint8_t pin) {
  if(pin < P30) { P1_MOD_OC &= ~(1 << pin); P1_DIR_PU |= (1 << pin); }
  else          { P3_MOD_OC &= ~(1 << (pin - P30)); P3_DIR_PU |= (1 << (pin - P30)); }
}

static void pinWrite(uint8_t pin, uint8_t value) {
  if(pin < P30) { if(value) P1 |= (1 << pin); else P1 &= ~(1 << pin); }
  else          { if(value) P3 |= (1 << (pin - P30)); else P3 &= ~(1 << (pin - P30)); }
}

static void releaseAll(void) {
  uint8_t i;
  for(i = 0; i < OTHER_COUNT; i++) pinInput(OTHERS[i]);
}

static void printPin(uint8_t pin) {
  KBD_type('P');
  KBD_type(pin < P30 ? '1' : '3');
  KBD_type('0' + (pin < P30 ? pin : pin - P30));
}

static void hold(uint8_t high, uint8_t low) {
  uint8_t tick;

  releaseAll();
  printPin(high);
  KBD_type('+');
  printPin(low);
  KBD_type('-');
  KBD_type(' ');

  pinWrite(high, 0);
  pinWrite(low, 0);
  pinOutput(high);
  pinOutput(low);

  for(tick = 0; tick < DWELL_TICKS; tick++) {
    pinWrite(high, 1);
    DLY_ms(ON_MS);
    pinWrite(high, 0);
    DLY_ms(OFF_MS);
  }
}

static void countdown(void) {
  uint8_t i;
  KBD_print("focus a text file: ");
  for(i = 10; i; i--) {
    if(i == 10) KBD_type('1');
    KBD_type('0' + (i % 10));
    KBD_type(' ');
    DLY_ms(1000);
  }
  KBD_print("GO ");
}

void main(void) {
  uint8_t a, i;

  CLK_config();
  DLY_ms(5);

  PIN_input_PU(KEY1_PIN);
  PIN_input_PU(KEY2_PIN);
  DLY_ms(1);

  if(!PIN_read(KEY1_PIN) && !PIN_read(KEY2_PIN)) BOOT_now();

  KBD_init();
  DLY_ms(1500);
  countdown();

  while(1) {
    for(a = 0; a < ANCHOR_COUNT; a++) {
      for(i = 0; i < OTHER_COUNT; i++) {
        if(OTHERS[i] == ANCHORS[a]) continue;
        hold(ANCHORS[a], OTHERS[i]);
        hold(OTHERS[i], ANCHORS[a]);
      }
    }
    KBD_print("[loop] ");
  }
}
