/**
 * SID The Kid
 * A SID player for the Gameboy Advance
 * /Mic, 2016
 */
#include <gba.h>
#include <stdint.h>
#include <string.h>
#include "sidplayer.h"

#define BUF_SIZE 656
#define FONT1_START_TILE 158
#define FONT2_START_TILE (FONT1_START_TILE+96)

int8_t buffer[2 * BUF_SIZE + 32];
uint32_t nextBuffer = 0;
uint8_t currSelection = 7;

const int16_t BLINK_TB[] = {
	-11,-11,-10,-10,-9,-9,-8,-7,-7,-6,-6,-5,-5,-4,-4,-3,-3,-3,-2,-2,-2,-1,-1,-1,
	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,-1,-1,-1,-2,-2,-2,-3,-3,-3,-4,-4,-5,-5,-6,
	-6,-7,-7,-8,-9,-9,-10,-10,-11,-12,-12,-13,-13,-14,-14,-15,-16,-16,-17,-17,-18,
	-18,-19,-19,-20,-20,-20,-21,-21,-21,-22,-22,-22,-23,-23,-23,-23,-23,-23,-23,-23,
	-23,-23,-23,-23,-23,-23,-23,-23,-23,-22,-22,-22,-21,-21,-21,-20,-20,-20,-19,-19,
	-18,-18,-17,-17,-16,-16,-15,-14,-14,-13,-13,-12
};
uint8_t blinkPos = 0;

uint16_t levelLut[6][3][256];

volatile bool switchedBuffer = false;

// From songs.s
extern uint8_t *SONG_POINTERS[];
extern uint32_t SONG_SIZES[];
extern uint32_t NUM_SONGS;

// From gfx.s
extern char bground[];
extern char arrow[];
extern u16 bgpal[];
extern u16 bgnam[];
extern char font[];
extern char font2[];


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

void initLevelLut() {
    int r,g,b;
    for (int i = 0; i < 6; i++) {
        for (int lvl = 0; lvl < 256; lvl++) {
            r = lvl*3/4 + (lvl/4)/(6-i);
            g = (lvl/2)/(6-i);
            b = 0;
            levelLut[i][0][lvl] = RGB8( (255 + r)*2/5, (241 + g)*2/5, (28 * r)>>8 );
            levelLut[i][1][lvl] = RGB8( r,             g,             0 );
            levelLut[i][2][lvl] = RGB8( (255 + r)*2/5, (241 + g)*2/5, (27 * r)>>8 );
        }
    }
}

void puts(const char* str, int x, const int y, const uint16_t pal, const uint16_t map, const uint16_t tilebase) {
	uint16_t *dest = MAP_BASE_ADR(map);
	dest += y*32 + x;
	for (; x < 29 && *str; str++) {
		char c = (*str == 'ä') ? 127 : *str;
		*dest++ = tilebase + (c - ' ') + (pal << 12);
		x++;
	}
}

void blinkHighlighted() {
	int16_t r = 23 + BLINK_TB[blinkPos];
	int16_t g = 17 + BLINK_TB[blinkPos];
	int16_t b = 7  + BLINK_TB[blinkPos];
	BG_COLORS[242] = RGB5((r > 0) ? r : 0,
	                      (g > 0) ? g : 0,
	                      (b > 0) ? b : 0);
	blinkPos = (blinkPos + 1) & 127;
}

void updateLevels() {
	int levels[6] = {0};
	static int prev_levels[6] = {0};

	levels[0] = mos6581_regs[0x20 + 0x46] & mos6581_regs[0x20 + 0x3C];
	levels[1] = (mos6581_regs[1]<<8) + mos6581_regs[0];
	levels[2] = mos6581_regs[0x20 + 0x58 + 0x46] & mos6581_regs[0x20 + 0x58 + 0x3C];
	levels[3] = (mos6581_regs[8]<<8) + mos6581_regs[7];
	levels[4] = mos6581_regs[0x20 + 0x58*2 + 0x46] & mos6581_regs[0x20 + 0x58*2 + 0x3C];
	levels[5] = (mos6581_regs[15]<<8) + mos6581_regs[14];

	levels[1] >>= 6; if (levels[1] > 255) levels[1] = 255;
	levels[3] >>= 6; if (levels[3] > 255) levels[3] = 255;
	levels[5] >>= 6; if (levels[5] > 255) levels[5] = 255;

	for (int i = 0; i < 6; i++) {
		if (prev_levels[i] > levels[i]) {
			prev_levels[i]-=4;
			if (prev_levels[i] < levels[i]) prev_levels[i] = levels[i];
		} else {
			prev_levels[i] = levels[i];
		}
		OBJ_COLORS[i*16 + 3] = levelLut[i][0][prev_levels[i]];
		OBJ_COLORS[i*16 + 4] = levelLut[i][1][prev_levels[i]];
		OBJ_COLORS[i*16 + 5] = levelLut[i][2][prev_levels[i]];
	}
}


int main() {
	uint16_t prevKeys = 0xffff;

	irqInit();
	irqSet( IRQ_TIMER1, timer1IrqHandler );
	irqEnable(IRQ_TIMER1);

	REG_DISPCNT = 0x80;  // Forced blank

	initLevelLut();

	// Clear BG1
	*((u32 *)MAP_BASE_ADR(31)) = ((u32)FONT1_START_TILE << 16) | FONT1_START_TILE;
	CpuFastSet( MAP_BASE_ADR(31), MAP_BASE_ADR(31), FILL | COPY32 | (0x800/4));

	// Clear BG2
	*((u32 *)MAP_BASE_ADR(28)) = ((u32)FONT2_START_TILE << 16) | FONT2_START_TILE;
	CpuFastSet( MAP_BASE_ADR(28), MAP_BASE_ADR(28), FILL | COPY32 | (0x800/4));

	CpuFastSet(bground, (u16*)VRAM,      5056/4 | COPY32);
	CpuFastSet(bgpal,   (u16*)BG_COLORS, 448/4  | COPY16);
	CpuFastSet(font,    (u16*)VRAM+2528, 3072/4 | COPY32);
	CpuFastSet(font2,   (u16*)VRAM+2528+1536, 3072/4 | COPY32);
	CpuFastSet(arrow,   (u16*)VRAM+0x8000, 288/4 | COPY32);

	// Song list colors
	BG_COLORS[226] = RGB5(0, 0, 0);
	BG_COLORS[225] = RGB5(26, 24,3);
	// Artist name colors
	BG_COLORS[234] = RGB5(31,31,31);
	BG_COLORS[233] = RGB5(0,0,0);
	// Highlighted song colors
	BG_COLORS[242] = RGB5(23, 17, 7);
	BG_COLORS[241] = RGB5(26, 24,3);

	BG_OFFSET[0].x = 0; BG_OFFSET[0].y = 0;
	BGCTRL[0] = SCREEN_BASE(16) | BG_256_COLOR | 1;

	BG_OFFSET[1].x = 2; BG_OFFSET[1].y = 0;
	BGCTRL[1] = SCREEN_BASE(31);

	BG_OFFSET[2].x = 0; BG_OFFSET[2].y = 2;
	BGCTRL[2] = SCREEN_BASE(28);

	uint16_t *dest = MAP_BASE_ADR(16);
	for (size_t y = 0; y < 20; y++) {
		for (size_t x = 0; x < 30; x++) {
			*dest++ = bgnam[y*30+x];
		}
		dest += 2;
	}

	for (int i = 0; i < NUM_SONGS; i++) {
		puts(SONG_POINTERS[i] + 22, 1, 2+i, 14, 31, FONT1_START_TILE);
	}
	puts(SONG_POINTERS[currSelection]+22, 1, 2+currSelection, 15, 31, FONT1_START_TILE);
	puts(SONG_POINTERS[currSelection]+54, 2, 19, 14, 28, FONT2_START_TILE);

	// Place all sprites off-screen
	for (int i = 0; i < 128; i++) {
		OAM[i].attr0 = 160;
		OAM[i].attr1 = 0;
	}

	for (int i = 0; i < 6; i++) {
		OBJ_COLORS[i*16+0] = 0x0F96;
		OBJ_COLORS[i*16+1] = 0x0FBF;
		OBJ_COLORS[i*16+2] = 0x0F1A;
		OBJ_COLORS[i*16+3] = 0x00C6;
		OBJ_COLORS[i*16+4] = 0x0000;
		OBJ_COLORS[i*16+5] = 0x00A5;

		for (int j = 0; j < 9; j++) {
			OAM[i*9 + j].attr0 = (j / 3) * 8 + (i + 1) * 21;
			OAM[i*9 + j].attr1 = (j % 3) * 8 + 217;
			OAM[i*9 + j].attr2 = j | OBJ_PALETTE(i);
		}
	}

	SetMode(MODE_0 | BG0_ON | BG1_ON | BG2_ON | OBJ_ON);

	sidPlayer_prepare(SONG_POINTERS[currSelection], SONG_SIZES[currSelection]);
	sidPlayer_run(BUF_SIZE, &buffer[0]);

	REG_SOUNDCNT_H = SNDA_VOL_100 | SNDA_R_ENABLE | SNDA_L_ENABLE | SNDA_RESET_FIFO;
	REG_SOUNDCNT_X = SNDSTAT_ENABLE;

	REG_TM0CNT_L = 65536 - 512;        // 32768 Hz
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
				blinkPos = 24;
				puts(SONG_POINTERS[currSelection]+22, 1, 2+currSelection, 14, 31, FONT1_START_TILE);
				currSelection--;
				puts(SONG_POINTERS[currSelection]+22, 1, 2+currSelection, 15, 31, FONT1_START_TILE);
			}
		} else if ((diff & KEY_DOWN) & keys) {
			if (currSelection < NUM_SONGS-1) {
				blinkPos = 24;
				puts(SONG_POINTERS[currSelection]+22, 1, 2+currSelection, 14, 31, FONT1_START_TILE);
				currSelection++;
				puts(SONG_POINTERS[currSelection]+22, 1, 2+currSelection, 15, 31, FONT1_START_TILE);
			}
		} else if ((diff & KEY_A) & keys) {
			memset(buffer, 0, 2 * BUF_SIZE + 32);
			sidPlayer_prepare(SONG_POINTERS[currSelection], SONG_SIZES[currSelection]);
			savePC = 0;
			puts("                                ", 2, 19, 14, 28, FONT2_START_TILE);
			puts(SONG_POINTERS[currSelection]+54, 2, 19, 14, 28, FONT2_START_TILE);
		}
		blinkHighlighted();
		updateLevels();
	}

	return 0;
}
