/**
 * SID The Kid
 * A SID player for the Gameboy Advance
 * /Mic, 2016
 */
#include <gba.h>
#include <stdint.h>
#include <string.h>
#include "sidplayer.h"

#define MAPADDRESS		MAP_BASE_ADR(31)

#define BUF_SIZE 656

int8_t buffer[2 * BUF_SIZE + 32];
uint32_t nextBuffer = 0;
uint8_t currSelection = 5;
volatile bool switchedBuffer = false;

// From songs.s
extern uint8_t *SONG_POINTERS[];
extern uint32_t SONG_SIZES[];
extern uint32_t NUM_SONGS;

// From gfs.s
extern char font[];


void timer1IrqHandler() {
	if (nextBuffer == 0) {
		REG_DMA1CNT = 0;
		REG_DMA1SAD = &buffer[0];
		REG_DMA1DAD = &REG_FIFO_A;
		REG_DMA1CNT = DMA_DST_FIXED | DMA_SRC_INC | DMA_REPEAT | DMA32 | DMA_SPECIAL | DMA_ENABLE;
	}
	REG_TM1CNT_L = 65536 - BUF_SIZE;
	REG_TM1CNT_H = TIMER_COUNT | TIMER_IRQ | TIMER_START;
	nextBuffer ^= 1;
	switchedBuffer = true;
}


void puts(const char* str, int x, const int y, const uint16_t pal) {
	uint16_t *dest = MAP_BASE_ADR(31);
	dest += y*32 + x;
	for (; x < 29 && *str; str++) {
		*dest++ = (*str - ' ') + (pal << 12);
		x++;
	}
}


int main() {
	uint16_t prevKeys = 0xffff;

	irqInit();
	irqSet(IRQ_TIMER1, timer1IrqHandler);
	irqEnable(IRQ_TIMER1);

	REG_DISPCNT = 0x80; // Forced blank

	BG_COLORS[0] = RGB8(73,112,163);
	BG_COLORS[1] = RGB8(133,243,188);
	BG_COLORS[17] = RGB8(160,255,224);
	BG_COLORS[33] = 0xffff;

	// Clear BG0
	*((u32 *)MAP_BASE_ADR(31)) = 0;
	CpuFastSet( MAP_BASE_ADR(31), MAP_BASE_ADR(31), FILL | COPY32 | (0x800/4));

	CpuFastSet(font, (u16*)VRAM, 3072/4 | COPY32);

	BG_OFFSET[0].x = 4; BG_OFFSET[0].y = 0;
	BGCTRL[0] = SCREEN_BASE(31);

	puts("SID The Kid", 9, 1, 1);
	puts("-----------", 9, 2, 1);
	puts("Mic, 2016", 10, 3, 1);

	for (int i = 0; i < NUM_SONGS; i++) {
		puts(SONG_POINTERS[i] + 22, 1, 5+i, 0);
	}
	puts(SONG_POINTERS[currSelection]+22, 1, 5+currSelection, 2);
	puts(">", 1, 18, 2);
	puts(SONG_POINTERS[currSelection]+54, 3, 18, 2);

	SetMode(MODE_0 | BG0_ON);		// screen mode & background to display

	sidPlayer_prepare(SONG_POINTERS[currSelection], SONG_SIZES[currSelection]);
	sidPlayer_run(BUF_SIZE, &buffer[0]);

	REG_SOUNDCNT_H = SNDA_VOL_100 | SNDA_R_ENABLE | SNDA_L_ENABLE | SNDA_RESET_FIFO;
	REG_SOUNDCNT_X = SNDSTAT_ENABLE;

	REG_TM0CNT_L = 65536 - 512;		// 32768 Hz
	REG_TM0CNT_H = TIMER_START;

	REG_TM1CNT_L = 65536 - BUF_SIZE;
	REG_TM1CNT_H = TIMER_COUNT | TIMER_IRQ | TIMER_START;

	REG_IME = 1;
	while (1) {
		while (!switchedBuffer) {}
		switchedBuffer = false;
		sidPlayer_run(BUF_SIZE, &buffer[nextBuffer * BUF_SIZE]);

		uint16_t keys = REG_KEYINPUT;
		uint16_t diff = keys ^ prevKeys;
		prevKeys = keys;
		if ((diff & KEY_UP) & keys) {
			if (currSelection > 0) {
				puts(SONG_POINTERS[currSelection]+22, 1, 5+currSelection, 0);
				currSelection--;
				puts(SONG_POINTERS[currSelection]+22, 1, 5+currSelection, 2);
			}
		} else if ((diff & KEY_DOWN) & keys) {
			if (currSelection < 11) {
				puts(SONG_POINTERS[currSelection]+22, 1, 5+currSelection, 0);
				currSelection++;
				puts(SONG_POINTERS[currSelection]+22, 1, 5+currSelection, 2);
			}
		} else if ((diff & KEY_A) & keys) {
			memset(buffer, 0, 2 * BUF_SIZE + 32);
			sidPlayer_prepare(SONG_POINTERS[currSelection], SONG_SIZES[currSelection]);
			savePC = 0;
			puts("                                ", 3, 18, 2);
			puts(SONG_POINTERS[currSelection]+54, 3, 18, 2);
		}
	}

	return 0;
}
