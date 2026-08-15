// ===================================================================================
// BitchBoy Nano - LED pin discovery
// ===================================================================================
//
// Walks the pins that aren't switches, driving one at a time, and types which pin and
// direction is live so you can read it off in a text editor. Left key steps to the
// next pin, right key flips between sourcing and sinking.
//
// Build with: make -C firmware SKETCH=ledscan.c bin
//
// Both keys held while plugging in still jumps to the bootloader.

#include <stdint.h>

#include "config.h"
#include "system.h"
#include "delay.h"
#include "gpio.h"
#include "usb_conkbd.h"

#define CANDIDATE_COUNT 8

void USB_interrupt(void);
void USB_ISR(void) __interrupt(INT_NO_USB) {
  USB_interrupt();
}

#define APPLY(pin, sinking)                                     \
  if(sinking) { PIN_output_OD(pin); PIN_low(pin);  }            \
  else        { PIN_output(pin);    PIN_high(pin); }

static void releaseAll(void) {
  PIN_input(P11); PIN_input(P15); PIN_input(P16); PIN_input(P17);
  PIN_input(P30); PIN_input(P31); PIN_input(P33); PIN_input(P34);
}

static void select(uint8_t index, uint8_t sinking) {
  releaseAll();
  switch(index) {
    case 0: KBD_print("P11"); APPLY(P11, sinking); break;
    case 1: KBD_print("P15"); APPLY(P15, sinking); break;
    case 2: KBD_print("P16"); APPLY(P16, sinking); break;
    case 3: KBD_print("P17"); APPLY(P17, sinking); break;
    case 4: KBD_print("P30"); APPLY(P30, sinking); break;
    case 5: KBD_print("P31"); APPLY(P31, sinking); break;
    case 6: KBD_print("P33"); APPLY(P33, sinking); break;
    case 7: KBD_print("P34"); APPLY(P34, sinking); break;
  }
  KBD_print(sinking ? " sink\n" : " source\n");
}

void main(void) {
  uint8_t index = 0, sinking = 0;
  __bit key1 = 0, key2 = 0, now;

  CLK_config();
  DLY_ms(5);

  PIN_input_PU(KEY1_PIN);
  PIN_input_PU(KEY2_PIN);
  DLY_ms(1);

  if(!PIN_read(KEY1_PIN) && !PIN_read(KEY2_PIN)) BOOT_now();

  KBD_init();
  DLY_ms(1500);                             // the host must finish enumerating before
                                            // the first line is typed, or it is lost
  select(index, sinking);

  while(1) {
    now = !PIN_read(KEY1_PIN);
    if(now != key1) {
      key1 = now;
      if(now) {
        if(++index >= CANDIDATE_COUNT) index = 0;
        select(index, sinking);
      }
      DLY_ms(KEY_DEBOUNCE_MS);
    }

    now = !PIN_read(KEY2_PIN);
    if(now != key2) {
      key2 = now;
      if(now) {
        sinking = !sinking;
        select(index, sinking);
      }
      DLY_ms(KEY_DEBOUNCE_MS);
    }

    DLY_ms(2);
  }
}
