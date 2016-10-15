/*
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

#define NLOG_LEVEL_ERROR 0

#include <gba.h>
#include <string.h>
#include <stdio.h>
#include "sidplayer.h"
#include "emu6502.h"

#define BYTESWAP(w) w = (((w) & 0xFF00) >> 8) | (((w) & 0x00FF) << 8)
#define WORDSWAP(d) d = (((d) & 0xFFFF0000) >> 16) | (((d) & 0x0000FFFF) << 16)

#define PAL_PHI 985248
#define PLAYBACK_RATE 19973

psidFileHeader fileHeader;
static bool prepared = false;

int masterVolume;

void sidPlayer_reset()
{
}


uint32_t __attribute__ ((section (".iwram"))) calc_step_scaled(uint32_t step)
{
	uint64_t temp64 = step;
	temp64 *= PAL_PHI << 8;
	return temp64 / PLAYBACK_RATE;
}

void sidPlayer_prepare(uint8_t *buffer, size_t bufLen)
{
    uint16_t *p16;

	prepared = false;

	memset(C64_RAM, 0, 65536);
    memcpy((char*)&fileHeader, buffer, 0x76);
    buffer += 0x76;
    bufLen -= 0x76;

#ifndef __32X__
	BYTESWAP(fileHeader.version);
	BYTESWAP(fileHeader.dataOffset);
	BYTESWAP(fileHeader.loadAddress);
	BYTESWAP(fileHeader.initAddress);
	BYTESWAP(fileHeader.playAddress);
	BYTESWAP(fileHeader.numSongs);
	BYTESWAP(fileHeader.firstSong);

	p16 = (uint16_t*)&fileHeader.speed;
	BYTESWAP(*p16);
	p16++;
	BYTESWAP(*p16);
	WORDSWAP(fileHeader.speed);
#endif

	if (fileHeader.version == 2) {
        memcpy(&fileHeader.flags, buffer, sizeof(fileHeader) - 0x76);
        buffer += sizeof(fileHeader) - 0x76;
        bufLen -= sizeof(fileHeader) - 0x76;
	}

	if (fileHeader.loadAddress == 0) {
		// First two bytes of data contain the load address
		memcpy(&fileHeader.loadAddress, buffer, 2);
		buffer += 2;
		bufLen -= 2;
	}

    memcpy(&C64_RAM[fileHeader.loadAddress], buffer, bufLen);

    if (!fileHeader.initAddress) fileHeader.initAddress = fileHeader.loadAddress;

	sidplayer_set_master_volume(0);

	sidmapper_reset();
	emu6502_reset();
	mos6581_reset();

	regS = 0xFF;
	prepared = true;
	sidPlayer_setSubSong(fileHeader.firstSong - 1);
}


void sidplayer_set_master_volume(int masterVol)
{
	masterVolume = masterVol;
}


static void __attribute__ ((noinline)) sidPlayer_execute6502(uint16_t address, uint32_t numCycles)
{
	// Note: this is crap, but it happens to work for some tunes.
	if (address) {
		// JSR loadAddress
		C64_RAM[0x413] = 0x20;
		C64_RAM[0x414] = address & 0xff;
		C64_RAM[0x415] = address >> 8;
		// -: JMP -
		C64_RAM[0x416] = 0x4c;
		C64_RAM[0x417] = 0x16;
		C64_RAM[0x418] = 0x04;
		regPC = 0x413;
		cpuCycles = 0;
		emu6502_run(numCycles);
	} else {
		uint8_t bankSelect = C64_RAM[0x01] & 3;
		if (bankSelect >= 2) {
			emu6502_setBrkVector(0x314);
		}
		// BRK
		C64_RAM[0x9ff0] = 0x00;
		// -: JMP -
		C64_RAM[0x9ff1] = 0x4c;
		C64_RAM[0x9ff2] = 0xf1;
		C64_RAM[0x9ff3] = 0x9f;
		regPC = 0x9ff0;
		cpuCycles = 0;
		emu6502_run(numCycles);
		emu6502_setBrkVector(0xfffe);
	}
}

void __attribute__ ((noinline)) sidPlayer_setSubSong(uint32_t subSong)
{
	regA = subSong;
	sidPlayer_execute6502(fileHeader.initAddress, 1500000);
}


void __attribute__ ((noinline)) sidPlayer_run(uint32_t numSamples, int8_t *buffer)
{
	sidPlayer_execute6502(fileHeader.playAddress, 20000);
  	uint32_t tstart = REG_VCOUNT;
	mos6581_run(numSamples, buffer);

  	// Performance measurement
  	uint32_t tend = REG_VCOUNT;
  	tend = (tend >= tstart) ? (tend - tstart) : (tend + 228 - tstart);
    if (tend > savePC) savePC = tend;
}


const psidFileHeader *sidPlayer_getFileHeader()
{
    return (const psidFileHeader*)&fileHeader;
}

const char *sidPlayer_getTitle()
{
    return (const char*)(fileHeader.title);
}

const char *sidPlayer_getAuthor()
{
    return (const char*)(fileHeader.author);
}

const char *sidPlayer_getCopyright()
{
    return (const char*)(fileHeader.copyright);
}

