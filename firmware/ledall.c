// ===================================================================================
// BitchBoy Nano - every ordered pin pair
// ===================================================================================
//
// Known so far, two common-anode LEDs:
//
//   right key   anode P1.1   green P3.4   blue P3.3
//   left  key   anode P1.7   green P3.0   blue P3.1
//
// Red has not turned up. The only combinations never driven are the switch pins
// against anything other than the two anodes, so this walks all 90 ordered pairs of
// all ten GPIOs the SOP-16 package exposes. Switch-pin pairs come first.
//
// If a full lap finds no red, red is not reachable from the CH552 at all.
//
// Build with: make -C firmware SKETCH=ledall.c bin
//
// Both keys held while plugging in still jumps to the bootloader.

#include <stdint.h>

#include "config.h"
#include "system.h"
#include "delay.h"
#include "gpio.h"
#include "usb_conkbd.h"

#define PIN_COUNT   10
#define DWELL_TICKS 25   // x 80ms

// 50% rather than the 25% used previously - red dies are usually the brightest of the
// three, so if it is still invisible it is not a duty cycle problem.
#define ON_MS   2
#define OFF_MS  2

void USB_interrupt(void);
void USB_ISR(void) __interrupt(INT_NO_USB) {
  USB_interrupt();
}

__code const uint8_t PINS[PIN_COUNT] = {
  P14, P32, P15, P16, P11, P17, P33, P34, P30, P31
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
  uint8_t i, j;

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
      for(j = 0; j < PIN_COUNT; j++) {
        if(i == j) continue;
        hold(PINS[i], PINS[j]);
      }
    }
    KBD_print("[loop] ");
  }
}
