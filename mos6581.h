/*
 * mos6581.h
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

#ifndef MOS6581_H_
#define MOS6581_H_

#include <stdint.h>
#include <stdbool.h>

#define MOS6581_REGISTER_BASE	 	0xD400

#define MOS6581_R_VOICE1_FREQ_LO  	0x00	// 16 bits, Fout = nnnn*0.0596
#define MOS6581_R_VOICE1_FREQ_HI  	0x01	// ...
#define MOS6581_R_VOICE1_PW_LO    	0x02	// 12 bits, PWout = nnn/40.95 %
#define MOS6581_R_VOICE1_PW_HI    	0x03	// ...
#define MOS6581_R_VOICE1_CTRL     	0x04
#define MOS6581_R_VOICE1_AD       	0x05  	// Attack rates: 2, 8, 16, 24, 38, 56, 68, 80, 100, 250, 500, 800, 1000, 3000, 5000, 8000 ms
#define MOS6581_R_VOICE1_SR       	0x06  	// DR rates: 6, 24, 48, 72, 114, 168, 204, 240, 300, 750, 1500, 2400, 3000, 9000, 15000, 24000 ms

#define MOS6581_R_VOICE2_FREQ_LO  	0x07
#define MOS6581_R_VOICE2_FREQ_HI  	0x08
#define MOS6581_R_VOICE2_PW_LO    	0x09
#define MOS6581_R_VOICE2_PW_HI    	0x0A
#define MOS6581_R_VOICE2_CTRL     	0x0B
#define MOS6581_R_VOICE2_AD       	0x0C
#define MOS6581_R_VOICE2_SR       	0x0D

#define MOS6581_R_VOICE3_FREQ_LO  	0x0E
#define MOS6581_R_VOICE3_FREQ_HI  	0x0F
#define MOS6581_R_VOICE3_PW_LO    	0x10
#define MOS6581_R_VOICE3_PW_HI    	0x11
#define MOS6581_R_VOICE3_CTRL     	0x12
#define MOS6581_R_VOICE3_AD       	0x13
#define MOS6581_R_VOICE3_SR       	0x14

#define MOS6581_R_FILTER_FC_LO    	0x15	// -----lll
#define MOS6581_R_FILTER_FC_HI    	0x16   	// hhhhhhhh
#define MOS6581_R_FILTER_RESFIL   	0x17
#define MOS6581_R_FILTER_MODEVOL  	0x18

// For R_VOICEx_CTRL
#define MOS6581_VOICE_CTRL_GATE		0x01
#define MOS6581_VOICE_CTRL_SYNC		0x02	// 1+3, 2+1, 3+2
#define MOS6581_VOICE_CTRL_RMOD		0x04 	// ...
#define MOS6581_VOICE_CTRL_TEST		0x08
#define MOS6581_VOICE_CTRL_TRIANGLE	0x10
#define MOS6581_VOICE_CTRL_SAW		0x20
#define MOS6581_VOICE_CTRL_PULSE	0x40
#define MOS6581_VOICE_CTRL_NOISE	0x80

// Envelope phases
enum
{
	EG_ATTACK  = 0,
	EG_DECAY   = 1,
	EG_SUSTAIN = 2,
	EG_RELEASE = 3,
};

struct mos6581Channel;

typedef struct
{
	int32_t pos, period, periodScaled, step;
	int32_t phase;
	struct mos6581Channel *channel;
	uint16_t sustainLevel;
	uint16_t clockDivider;
	bool clocked;
	uint8_t out;
} mos6581EnvelopeGenerator;


struct mos6581;


struct mos6581Channel
{
	uint32_t pos, period, step, stepScaled;
	uint32_t lfsr;
	int32_t index, prevIndex, nextIndex;
	int32_t regBlock, nextRegBlock;
	struct mos6581 *chip;
	mos6581EnvelopeGenerator eg;
	int16_t out;
	uint16_t duty;
	uint16_t vol;
	uint32_t outputMask;
};

struct mos6581
{
	struct mos6581Channel channels[3];
	uint8_t regs[MOS6581_R_FILTER_MODEVOL + 1];
};

extern uint8_t mos6581_regs[];

void mos6581_reset();
void mos6581_run(uint32_t numSamples, int8_t *buffer);
void mos6581_write(uint32_t addr, uint8_t data);

#endif
