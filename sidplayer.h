/*
 * sidplayer.h
 *
 *  Created on: Oct 9, 2013
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

#ifndef SIDPLAYER_H_
#define SIDPLAYER_H_

#include <stddef.h>
#include <stdint.h>
#include "emu6502.h"
#include "mos6581.h"
#include "sidmapper.h"

typedef struct __attribute__ ((__packed__))
{
    char magic[4];
    uint16_t version;
    uint16_t dataOffset;
    uint16_t loadAddress;
    uint16_t initAddress;
    uint16_t playAddress;
    uint16_t numSongs;
    uint16_t firstSong;	// 1-based
    uint32_t speed;
    char title[32];		// ASCIIZ
    char author[32];	// ...
    char copyright[32];	// ...
    // END of v1 header
    uint16_t flags;
    uint8_t startPage;
    uint8_t pageLength;
    uint16_t reserved;
    // END of v2 header
} psidFileHeader;

void sidPlayer_prepare(uint8_t *buffer, size_t bufLen);
void sidPlayer_run(uint32_t numSamples, int8_t *buffer);
void sidPlayer_reset();

void sidPlayer_setSubSong(uint32_t subSong);
void sidplayer_set_master_volume(int masterVol);

const psidFileHeader *sidPlayer_getFileHeader();

const char *sidPlayer_getTitle();
const char *sidPlayer_getAuthor();
const char *sidPlayer_getCopyright();

#endif /* SIDPLAYER_H_ */
