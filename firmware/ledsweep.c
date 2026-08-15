// ===================================================================================
// BitchBoy Nano - exhaustive LED discovery
// ===================================================================================
//
// Runs every theory we have, unattended, across all ten GPIOs the SOP-16 package
// exposes - including the two switch pins, which earlier sweeps skipped:
//
//   1. static push-pull HIGH        (pin -> LED -> GND)
//   2. static push-pull LOW         (VCC -> LED -> pin)
//   3. WS2812 bitstream at 800kHz   (single-wire addressable)
//   4. APA102 clock + data          (two-wire addressable, every ordered pin pair)
//
// Nothing is typed with a newline, so if the wrong window has focus you get one long
// harmless line instead of a hundred submitted commands. Ten second countdown first.
//
// Build with: make -C firmware SKETCH=ledsweep.c bin
//
// Both keys held while plugging in still jumps to the bootloader.

#include <stdint.h>

#include "config.h"
#include "system.h"
#include "delay.h"
#include "gpio.h"
#include "usb_conkbd.h"

#define CANDIDATE_COUNT 10
#define PIXELS          8
#define DWELL_TICKS     15    // x 100ms
#define LEVEL           0xFF  // the seller's photos only show these lit in the dark

#if F_CPU != 16000000
  #error NeoPixel timing here is only calculated for 16 MHz
#endif

// The bit transmission loop takes 11 clock cycles; see wagiminator's neo.c.
#define T1H_DELAY \
  nop             \
  nop             \
  nop             \
  nop             \
  nop             \
  nop
#define TCT_DELAY \
  nop             \
  nop

void USB_interrupt(void);
void USB_ISR(void) __interrupt(INT_NO_USB) {
  USB_interrupt();
}

#define NEO_FN sendP11
#define NEOPIN PIN_asm(P11)
#include "neo_send.h"
#undef NEO_FN
#undef NEOPIN

#define NEO_FN sendP14
#define NEOPIN PIN_asm(P14)
#include "neo_send.h"
#undef NEO_FN
#undef NEOPIN

#define NEO_FN sendP15
#define NEOPIN PIN_asm(P15)
#include "neo_send.h"
#undef NEO_FN
#undef NEOPIN

#define NEO_FN sendP16
#define NEOPIN PIN_asm(P16)
#include "neo_send.h"
#undef NEO_FN
#undef NEOPIN

#define NEO_FN sendP17
#define NEOPIN PIN_asm(P17)
#include "neo_send.h"
#undef NEO_FN
#undef NEOPIN

#define NEO_FN sendP30
#define NEOPIN PIN_asm(P30)
#include "neo_send.h"
#undef NEO_FN
#undef NEOPIN

#define NEO_FN sendP31
#define NEOPIN PIN_asm(P31)
#include "neo_send.h"
#undef NEO_FN
#undef NEOPIN

#define NEO_FN sendP32
#define NEOPIN PIN_asm(P32)
#include "neo_send.h"
#undef NEO_FN
#undef NEOPIN

#define NEO_FN sendP33
#define NEOPIN PIN_asm(P33)
#include "neo_send.h"
#undef NEO_FN
#undef NEOPIN

#define NEO_FN sendP34
#define NEOPIN PIN_asm(P34)
#include "neo_send.h"
#undef NEO_FN
#undef NEOPIN

__code const uint8_t CANDIDATES[CANDIDATE_COUNT] = {
  P11, P14, P15, P16, P17, P30, P31, P32, P33, P34
};

// gpio.h's pin macros paste the pin name into an SFR bit symbol, so they only take
// literals. The sweep needs to pick pins at runtime, hence these.
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
  for(i = 0; i < CANDIDATE_COUNT; i++) pinInput(CANDIDATES[i]);
}

static void printPin(uint8_t pin) {
  KBD_type('P');
  KBD_type(pin < P30 ? '1' : '3');
  KBD_type('0' + (pin < P30 ? pin : pin - P30));
}

static void neoByte(uint8_t index, uint8_t value) {
  switch(index) {
    case 0: sendP11(value); break;
    case 1: sendP14(value); break;
    case 2: sendP15(value); break;
    case 3: sendP16(value); break;
    case 4: sendP17(value); break;
    case 5: sendP30(value); break;
    case 6: sendP31(value); break;
    case 7: sendP32(value); break;
    case 8: sendP33(value); break;
    case 9: sendP34(value); break;
  }
}

// A USB interrupt mid-byte stretches a bit past the pixel's latch time and the whole
// chain resets, so the burst has to be uninterrupted.
static void neoBlast(uint8_t index) {
  uint8_t i;
  EA = 0;
  for(i = 0; i < PIXELS * 3; i++) neoByte(index, LEVEL);
  EA = 1;
  DLY_us(281);
}

static void apaByte(uint8_t clock, uint8_t data, uint8_t value) {
  uint8_t i;
  for(i = 0; i < 8; i++) {
    pinWrite(data, (value & 0x80) ? 1 : 0);
    pinWrite(clock, 1);
    pinWrite(clock, 0);
    value <<= 1;
  }
}

static void apaBlast(uint8_t clock, uint8_t data) {
  uint8_t i;
  for(i = 0; i < 4; i++) apaByte(clock, data, 0x00);
  for(i = 0; i < PIXELS; i++) {
    apaByte(clock, data, 0xFF);   // 111 + 5-bit global brightness, all on
    apaByte(clock, data, LEVEL);  // blue
    apaByte(clock, data, LEVEL);  // green
    apaByte(clock, data, LEVEL);  // red
  }
  for(i = 0; i < 4; i++) apaByte(clock, data, 0xFF);
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
  uint8_t i, j, tick;

  CLK_config();
  DLY_ms(5);

  PIN_input_PU(KEY1_PIN);
  PIN_input_PU(KEY2_PIN);
  DLY_ms(1);

  if(!PIN_read(KEY1_PIN) && !PIN_read(KEY2_PIN)) BOOT_now();

  KBD_init();
  DLY_ms(1500);
  countdown();

  KBD_print("[static-high] ");
  for(i = 0; i < CANDIDATE_COUNT; i++) {
    releaseAll();
    printPin(CANDIDATES[i]);
    KBD_type(' ');
    pinWrite(CANDIDATES[i], 1);
    pinOutput(CANDIDATES[i]);
    for(tick = 0; tick < DWELL_TICKS; tick++) DLY_ms(100);
  }

  KBD_print("[static-low] ");
  for(i = 0; i < CANDIDATE_COUNT; i++) {
    releaseAll();
    printPin(CANDIDATES[i]);
    KBD_type(' ');
    pinWrite(CANDIDATES[i], 0);
    pinOutput(CANDIDATES[i]);
    for(tick = 0; tick < DWELL_TICKS; tick++) DLY_ms(100);
  }

  KBD_print("[ws2812] ");
  for(i = 0; i < CANDIDATE_COUNT; i++) {
    releaseAll();
    printPin(CANDIDATES[i]);
    KBD_type(' ');
    pinWrite(CANDIDATES[i], 0);
    pinOutput(CANDIDATES[i]);
    for(tick = 0; tick < DWELL_TICKS; tick++) { neoBlast(i); DLY_ms(100); }
  }

  KBD_print("[apa102 clock>data] ");
  for(i = 0; i < CANDIDATE_COUNT; i++) {
    for(j = 0; j < CANDIDATE_COUNT; j++) {
      if(i == j) continue;
      releaseAll();
      printPin(CANDIDATES[i]);
      KBD_type('>');
      printPin(CANDIDATES[j]);
      KBD_type(' ');
      pinWrite(CANDIDATES[i], 0);
      pinWrite(CANDIDATES[j], 0);
      pinOutput(CANDIDATES[i]);
      pinOutput(CANDIDATES[j]);
      for(tick = 0; tick < DWELL_TICKS; tick++) { apaBlast(CANDIDATES[i], CANDIDATES[j]); DLY_ms(100); }
    }
  }

  releaseAll();
  KBD_print("DONE ");
  while(1) DLY_ms(100);
}
