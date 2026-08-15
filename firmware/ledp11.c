// ===================================================================================
// BitchBoy Nano - P1.1 LED characterisation
// ===================================================================================
//
// The exhaustive sweep flickered on pairs clocked from P1.1, which points at P1.1
// being a single-wire addressable LED line that wants slower timing than the 800kHz
// WS2812 stream we tried. This steps through, under key control:
//
//   steps 0-6   APA102 with clock P1.1, data on each non-switch pin (reconfirmation)
//   steps 7-14  single-wire on P1.1 across a range of bit timings (the hypothesis)
//
// P1.4 and P3.2 are deliberately not driven so the keys stay readable. Nothing is
// typed with a newline.
//
// Left key steps forward, right key steps back.
//
// Build with: make -C firmware SKETCH=ledp11.c bin
//
// Both keys held while plugging in still jumps to the bootloader.

#include <stdint.h>

#include "config.h"
#include "system.h"
#include "delay.h"
#include "gpio.h"
#include "usb_conkbd.h"

#define LED_PIN      P11
#define DATA_COUNT   7
#define TIMING_COUNT 8
#define STEP_COUNT   (DATA_COUNT + TIMING_COUNT)
#define PIXELS       8

void USB_interrupt(void);
void USB_ISR(void) __interrupt(INT_NO_USB) {
  USB_interrupt();
}

__code const uint8_t DATA_PINS[DATA_COUNT] = { P15, P16, P17, P30, P31, P33, P34 };

// High time and low time per bit, in spin units, walking from roughly WS2812 speed
// down to WS2811-slow and below. Every byte sent is 0xFF, so only the 1-bit shape
// matters and a mistimed stream still reads as "bright" rather than as a colour that
// might be invisible.
__code const uint8_t TIMINGS[TIMING_COUNT][2] = {
  {  0,  0 },
  {  1,  0 },
  {  2,  1 },
  {  4,  2 },
  {  6,  3 },
  { 10,  5 },
  { 16,  8 },
  { 24, 12 },
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

static void releaseData(void) {
  uint8_t i;
  for(i = 0; i < DATA_COUNT; i++) pinInput(DATA_PINS[i]);
}

static void printPin(uint8_t pin) {
  KBD_type('P');
  KBD_type(pin < P30 ? '1' : '3');
  KBD_type('0' + (pin < P30 ? pin : pin - P30));
}

static void spin(uint8_t units) {
  while(units) {
    units--;
    __asm
      nop
      nop
    __endasm;
  }
}

// The clock deliberately goes through the slow runtime pinWrite rather than the fast
// PIN_high/PIN_low macros. That is what ledsweep.c did when the LEDs first flickered,
// and the effect disappears when the waveform speeds up.
static void apaByte(uint8_t data, uint8_t value) {
  uint8_t i;
  for(i = 0; i < 8; i++) {
    pinWrite(data, (value & 0x80) ? 1 : 0);
    pinWrite(LED_PIN, 1);
    pinWrite(LED_PIN, 0);
    value <<= 1;
  }
}

static void apaBlast(uint8_t data) {
  uint8_t i;
  for(i = 0; i < 4; i++) apaByte(data, 0x00);
  for(i = 0; i < PIXELS; i++) {
    apaByte(data, 0xFF); apaByte(data, 0xFF);
    apaByte(data, 0xFF); apaByte(data, 0xFF);
  }
  for(i = 0; i < 4; i++) apaByte(data, 0xFF);
}

// t0 spins for zero units, so it lands at the same rate as the APA102 clock above -
// the condition that produced light. Higher steps stretch out from there.
static void wireBlast(uint8_t timing) {
  uint8_t byte, bit;
  uint8_t high = TIMINGS[timing][0];
  uint8_t low  = TIMINGS[timing][1];

  EA = 0;
  for(byte = 0; byte < PIXELS * 3; byte++) {
    for(bit = 0; bit < 8; bit++) {
      pinWrite(LED_PIN, 1);
      spin(high);
      pinWrite(LED_PIN, 0);
      spin(low);
    }
  }
  EA = 1;
  DLY_us(300);
}

static void announce(uint8_t step) {
  if(step < DATA_COUNT) {
    KBD_print("apa P11>");
    printPin(DATA_PINS[step]);
    KBD_type(' ');
  } else {
    KBD_print("wire P11 t");
    KBD_type('0' + (step - DATA_COUNT));
    KBD_type(' ');
  }
}

static void arm(uint8_t step) {
  releaseData();
  PIN_low(LED_PIN);
  PIN_output(LED_PIN);
  if(step < DATA_COUNT) {
    pinWrite(DATA_PINS[step], 0);
    pinOutput(DATA_PINS[step]);
  }
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

    if(step < DATA_COUNT) apaBlast(DATA_PINS[step]);
    else                  wireBlast(step - DATA_COUNT);

    DLY_ms(20);
  }
}
