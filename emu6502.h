/*
 * emu6502.h
 *
 *  Created on: Oct 8, 2013
 *
 * Copyright 2013 Mic
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#ifndef EMU6502_H_
#define EMU6502_H_

#include <stdint.h>

enum {
    EMU6502_FLAG_C = 0x01,
    EMU6502_FLAG_Z = 0x02,
    EMU6502_FLAG_I = 0x04,
    EMU6502_FLAG_D = 0x08,
    EMU6502_FLAG_B = 0x10,
    EMU6502_FLAG_V = 0x40,
    EMU6502_FLAG_N = 0x80,
};

void emu6502_reset();
void emu6502_run(uint32_t maxCycles);
void emu6502_setBrkVector(uint32_t vector);
void emu6502_irq(uint32_t vector);
extern uint32_t regA, regX, regY, regS, regF, regPC, cpuCycles;
extern uint32_t savePC;

#endif /* EMU6502_H_ */
