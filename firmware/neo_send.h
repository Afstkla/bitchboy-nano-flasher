// Included once per candidate pin, with NEO_FN and NEOPIN redefined each time.
// Deliberately has no include guard.
//
// Body is wagiminator's NEO_sendByte from CH552-MacroPad-mini (CC BY-SA 3.0); the pin
// lives in the inline assembly, so the only way to sweep pins is to stamp out one
// copy per pin.

void NEO_FN(uint8_t data) {
  data;
  __asm
    .even
    mov  r7, #8
    xch  a, dpl
    01$:
    rlc  a
    setb NEOPIN
    mov  NEOPIN, c
    T1H_DELAY
    clr  NEOPIN
    TCT_DELAY
    djnz r7, 01$
  __endasm;
}
