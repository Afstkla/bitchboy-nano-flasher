// ===================================================================================
// USB HID Functions for CH551, CH552 and CH554
// ===================================================================================

#pragma once
#include <stdint.h>

void HID_init(void);                                      // setup USB-HID
void HID_sendReport(__xdata uint8_t* buf, uint8_t len);   // send HID report
void MIDI_send(uint8_t status, uint8_t data1, uint8_t data2);  // send MIDI message
