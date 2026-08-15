// ===================================================================================
// BitchBoy Nano - charlieplexed LED discovery
// ===================================================================================
//
// The LEDs are wired between pairs of pins, not between a pin and a rail - which is
// why every single-pin sweep came up dark. This drives one pin high and one pin low
// with every other candidate left high-impedance, walking all ordered pairs.
//
// P1.1, P3.3 and P3.4 come first because apa P11>P33 and P11>P34 already produced
// blue and green under one keypad. The remaining four LEDs, red included, should be
// on pairs those runs never drove.
//
// P1.4 and P3.2 stay undriven so the keys keep working.
//
// Left key steps forward, right key steps back.
//
// Build with: make -C firmware SKETCH=ledpair.c bin
//
// Both keys held while plugging in still jumps to the bootloader.

#include <stdint.h>

#include "config.h"
#include "system.h"
#include "delay.h"
#include "gpio.h"
#include "usb_conkbd.h"

#define PIN_COUNT  8
#define STEP_COUNT (PIN_COUNT * (PIN_COUNT - 1))

// Driven at 25% rather than DC: if these LEDs have no series resistors, a hard rail to
// rail drive through a die is more current than it is built for.
#define ON_MS   1
#define OFF_MS  3

void USB_interrupt(void);
void USB_ISR(void) __interrupt(INT_NO_USB) {
  USB_interrupt();
}

__code const uint8_t PINS[PIN_COUNT] = { P11, P33, P34, P15, P16, P17, P30, P31 };

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

static uint8_t highPin(uint8_t step) {
  return PINS[step / (PIN_COUNT - 1)];
}

static uint8_t lowPin(uint8_t step) {
  uint8_t high = step / (PIN_COUNT - 1);
  uint8_t low  = step % (PIN_COUNT - 1);
  return PINS[low >= high ? low + 1 : low];
}

static void announce(uint8_t step) {
  printPin(highPin(step));
  KBD_type('+');
  printPin(lowPin(step));
  KBD_type('-');
  KBD_type(' ');
}

static void arm(uint8_t step) {
  releaseAll();
  pinWrite(highPin(step), 0);
  pinWrite(lowPin(step), 0);
  pinOutput(highPin(step));
  pinOutput(lowPin(step));
}

void main(void) {
  uint8_t step = 0;
  __bit key1 = 0, key2 = 0, now;

  CLK_config();
  DLY_ms(5);

  PIN_input_PU(KEY1_PIN);
  PIN_input_PU(KEY2_PIN);
  DLY_ms(1);

  if(!PIN_read(KEY1_PIN) && !PIN_read(KEY2_PIN)) BOOT_now();

  KBD_init();
  DLY_ms(1500);
  announce(step);
  arm(step);

  while(1) {
    now = !PIN_read(KEY1_PIN);
    if(now != key1) {
      key1 = now;
      if(now) {
        if(++step >= STEP_COUNT) step = 0;
        announce(step);
        arm(step);
      }
      DLY_ms(KEY_DEBOUNCE_MS);
    }

    now = !PIN_read(KEY2_PIN);
    if(now != key2) {
      key2 = now;
      if(now) {
        step = step ? step - 1 : STEP_COUNT - 1;
        announce(step);
        arm(step);
      }
      DLY_ms(KEY_DEBOUNCE_MS);
    }

    pinWrite(highPin(step), 1);
    DLY_ms(ON_MS);
    pinWrite(highPin(step), 0);
    DLY_ms(OFF_MS);
  }
}
