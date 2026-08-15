// ===================================================================================
// BitchBoy Nano - one pin against the rails
// ===================================================================================
//
// All 90 ordered pin pairs are exhausted. The remaining case is an LED wired between
// a single pin and a rail: anode on VCC with the cathode pulled low, or cathode on
// GND with the anode driven high.
//
// ledsweep.c did cover this, but at 1.5s per pin at the very start of a long run.
// This does nothing else, 4s per step, so it cannot be missed.
//
// P1.5 and P1.6 first: every other GPIO is accounted for as an anode, a cathode or a
// switch, which makes those two the only candidates left for the red channel.
//
// Build with: make -C firmware SKETCH=ledrail.c bin
//
// Both keys held while plugging in still jumps to the bootloader.

#include <stdint.h>

#include "config.h"
#include "system.h"
#include "delay.h"
#include "gpio.h"
#include "usb_conkbd.h"

#define PIN_COUNT   10
#define DWELL_TICKS 50   // x 80ms

void USB_interrupt(void);
void USB_ISR(void) __interrupt(INT_NO_USB) {
  USB_interrupt();
}

__code const uint8_t PINS[PIN_COUNT] = {
  P15, P16, P11, P17, P33, P34, P30, P31, P14, P32
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
  for(i = 0; i < PIN_COUNT; i++) pinInput(PINS[i]);
}

static void printPin(uint8_t pin) {
  KBD_type('P');
  KBD_type(pin < P30 ? '1' : '3');
  KBD_type('0' + (pin < P30 ? pin : pin - P30));
}

static void hold(uint8_t pin, uint8_t level) {
  uint8_t tick;

  releaseAll();
  printPin(pin);
  KBD_type(level ? '+' : '-');
  KBD_type(' ');

  pinWrite(pin, level);
  pinOutput(pin);

  for(tick = 0; tick < DWELL_TICKS; tick++) DLY_ms(80);
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
  uint8_t i;

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
    for(i = 0; i < PIN_COUNT; i++) {
      hold(PINS[i], 0);
      hold(PINS[i], 1);
    }
    KBD_print("[loop] ");
  }
}
