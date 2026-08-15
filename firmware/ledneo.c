// ===================================================================================
// BitchBoy Nano - NeoPixel pin discovery
// ===================================================================================
//
// The GPIO sweep (ledscan.c) found nothing, and the LEDs turned out to be 4-pad
// WS2812-alikes, which ignore a statically driven pin. This walks the same candidate
// pins sending an actual 800kHz bitstream instead.
//
// Left key steps to the next pin, right key cycles the colour. The live pin is typed
// out, same as ledscan.c.
//
// Build with: make -C firmware SKETCH=ledneo.c bin
//
// Both keys held while plugging in still jumps to the bootloader.

#include <stdint.h>

#include "config.h"
#include "system.h"
#include "delay.h"
#include "gpio.h"
#include "usb_conkbd.h"

#define CANDIDATE_COUNT 8
#define PIXELS          8     // covers a longer chain than the two we expect
#define LEVEL           0x30  // 2 pixels at full white would blow the 50mA descriptor

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
  nop                       // 10 - 4 = 6 clock cycles for min 625ns
#define TCT_DELAY \
  nop             \
  nop                       // 19 - 6 - 11 = 2 clock cycles for min 1150ns

void USB_interrupt(void);
void USB_ISR(void) __interrupt(INT_NO_USB) {
  USB_interrupt();
}

#define NEO_FN sendP11
#define NEOPIN PIN_asm(P11)
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

static void releaseAll(void) {
  PIN_input(P11); PIN_input(P15); PIN_input(P16); PIN_input(P17);
  PIN_input(P30); PIN_input(P31); PIN_input(P33); PIN_input(P34);
}

static void arm(uint8_t index) {
  releaseAll();
  switch(index) {
    case 0: PIN_low(P11); PIN_output(P11); break;
    case 1: PIN_low(P15); PIN_output(P15); break;
    case 2: PIN_low(P16); PIN_output(P16); break;
    case 3: PIN_low(P17); PIN_output(P17); break;
    case 4: PIN_low(P30); PIN_output(P30); break;
    case 5: PIN_low(P31); PIN_output(P31); break;
    case 6: PIN_low(P33); PIN_output(P33); break;
    case 7: PIN_low(P34); PIN_output(P34); break;
  }
}

static void sendByte(uint8_t index, uint8_t value) {
  switch(index) {
    case 0: sendP11(value); break;
    case 1: sendP15(value); break;
    case 2: sendP16(value); break;
    case 3: sendP17(value); break;
    case 4: sendP30(value); break;
    case 5: sendP31(value); break;
    case 6: sendP33(value); break;
    case 7: sendP34(value); break;
  }
}

// Interrupts must stay off for the whole burst - a USB interrupt mid-byte stretches a
// bit beyond the pixel's latch time and the chain resets.
static void blast(uint8_t index, uint8_t r, uint8_t g, uint8_t b) {
  uint8_t i;
  EA = 0;
  for(i = 0; i < PIXELS; i++) {
    sendByte(index, g);
    sendByte(index, r);
    sendByte(index, b);
  }
  EA = 1;
  DLY_us(281);
}

static void announce(uint8_t index) {
  switch(index) {
    case 0: KBD_print("P11\n"); break;
    case 1: KBD_print("P15\n"); break;
    case 2: KBD_print("P16\n"); break;
    case 3: KBD_print("P17\n"); break;
    case 4: KBD_print("P30\n"); break;
    case 5: KBD_print("P31\n"); break;
    case 6: KBD_print("P33\n"); break;
    case 7: KBD_print("P34\n"); break;
  }
}

void main(void) {
  uint8_t index = 0, colour = 0;
  __bit key1 = 0, key2 = 0, now;

  CLK_config();
  DLY_ms(5);

  PIN_input_PU(KEY1_PIN);
  PIN_input_PU(KEY2_PIN);
  DLY_ms(1);

  if(!PIN_read(KEY1_PIN) && !PIN_read(KEY2_PIN)) BOOT_now();

  KBD_init();
  DLY_ms(1500);
  announce(index);
  arm(index);

  while(1) {
    now = !PIN_read(KEY1_PIN);
    if(now != key1) {
      key1 = now;
      if(now) {
        if(++index >= CANDIDATE_COUNT) index = 0;
        announce(index);
        arm(index);
      }
      DLY_ms(KEY_DEBOUNCE_MS);
    }

    now = !PIN_read(KEY2_PIN);
    if(now != key2) {
      key2 = now;
      if(now) colour = (colour + 1) & 3;
      DLY_ms(KEY_DEBOUNCE_MS);
    }

    switch(colour) {
      case 0:  blast(index, LEVEL, LEVEL, LEVEL); break;
      case 1:  blast(index, LEVEL,     0,     0); break;
      case 2:  blast(index,     0, LEVEL,     0); break;
      default: blast(index,     0,     0, LEVEL); break;
    }

    DLY_ms(20);
  }
}
