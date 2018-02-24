@ A SID chip emulator for the ARM7TDMI
@ /Mic, 2016

.global mos6581_reset
.global mos6581_run
.global mos6581_write
.global mos6581_regs

.arm
.section .iwram

@ SID registers
.equ MOS6581_R_VOICE1_FREQ_LO, 	0x00	@ 16 bits, Fout = nnnn*0.0596
.equ MOS6581_R_VOICE1_FREQ_HI, 	0x01	@ ...
.equ MOS6581_R_VOICE1_PW_LO,   	0x02	@ 12 bits, PWout = nnn/40.95 %
.equ MOS6581_R_VOICE1_PW_HI,   	0x03	@ ...
.equ MOS6581_R_VOICE1_CTRL,    	0x04
.equ MOS6581_R_VOICE1_AD,      	0x05  	@ Attack rates: 2, 8, 16, 24, 38, 56, 68, 80, 100, 250, 500, 800, 1000, 3000, 5000, 8000 ms
.equ MOS6581_R_VOICE1_SR,      	0x06  	@ DR rates: 6, 24, 48, 72, 114, 168, 204, 240, 300, 750, 1500, 2400, 3000, 9000, 15000, 24000 ms

.equ MOS6581_R_VOICE2_FREQ_LO, 	0x07
.equ MOS6581_R_VOICE2_FREQ_HI, 	0x08
.equ MOS6581_R_VOICE2_PW_LO,   	0x09
.equ MOS6581_R_VOICE2_PW_HI,   	0x0A
.equ MOS6581_R_VOICE2_CTRL,    	0x0B
.equ MOS6581_R_VOICE2_AD,      	0x0C
.equ MOS6581_R_VOICE2_SR,      	0x0D

.equ MOS6581_R_VOICE3_FREQ_LO, 	0x0E
.equ MOS6581_R_VOICE3_FREQ_HI, 	0x0F
.equ MOS6581_R_VOICE3_PW_LO,   	0x10
.equ MOS6581_R_VOICE3_PW_HI,   	0x11
.equ MOS6581_R_VOICE3_CTRL,    	0x12
.equ MOS6581_R_VOICE3_AD,      	0x13
.equ MOS6581_R_VOICE3_SR,      	0x14

.equ MOS6581_R_FILTER_FC_LO,   	0x15	@ -----lll
.equ MOS6581_R_FILTER_FC_HI,   	0x16   	@ hhhhhhhh
.equ MOS6581_R_FILTER_RESFIL,  	0x17
.equ MOS6581_R_FILTER_MODEVOL, 	0x18

@ For R_VOICEx_CTRL
.equ MOS6581_VOICE_CTRL_GATE,   0x01
.equ MOS6581_VOICE_CTRL_SYNC,   0x02	@ 1+3, 2+1, 3+2
.equ MOS6581_VOICE_CTRL_RMOD,   0x04 	@ ...
.equ MOS6581_VOICE_CTRL_TEST,   0x08
.equ MOS6581_VOICE_CTRL_TRIANGLE,0x10
.equ MOS6581_VOICE_CTRL_SAW,    0x20
.equ MOS6581_VOICE_CTRL_PULSE,  0x40
.equ MOS6581_VOICE_CTRL_NOISE,  0x80

@ Channel structure offsets
.equ CHN_POS,			0x00
.equ CHN_PERIOD,		0x04
.equ CHN_STEP,			0x08
.equ CHN_STEP_SCALED,	0x0C
.equ CHN_LFSR,			0x10
.equ CHN_INDEX,			0x14
.equ CHN_PREV_CHN,		0x18
.equ CHN_NEXT_CHN,		0x1C
.equ CHN_EG_POS,		0x20
.equ CHN_EG_PERIOD,		0x24
.equ CHN_EG_STEP,		0x28
.equ CHN_EG_PER_SCALED,	0x2C
.equ CHN_EG_PHASE,		0x30
.equ CHN_EG_SUS_LEVEL,	0x34	@ hword
.equ CHN_EG_CLK_DIV,	0x36	@ hword
.equ CHN_EG_CLOCKED,	0x38
.equ CHN_OUTPUT_MASK,	0x3C
.equ CHN_OUT,			0x40	@ hword
.equ CHN_DUTY,			0x42	@ hword
.equ CHN_VOL,			0x44	@ hword
.equ CHN_EG_OUT,		0x46
.equ CHN_NEXT_REG_BLOCK,0x48
.equ CHN_NOISE_OUT,		0x52
.equ SIZEOF_CHN, 0x58

@ Envelope phases
.equ EG_ATTACK,  0
.equ EG_DECAY,   1
.equ EG_SUSTAIN, 2
.equ EG_RELEASE, 3

@ Timing constants
.equ PAL_PHI, 985248
.equ PLAYBACK_RATE, 32768
.equ EG_STEP_SHIFT, 8
.equ EG_STEP, (((PAL_PHI<<EG_STEP_SHIFT)+(PLAYBACK_RATE/2))/PLAYBACK_RATE)
.equ OSC_STEP_SHIFT, 8
.equ OSC_STEP, (((PAL_PHI<<(OSC_STEP_SHIFT))+(PLAYBACK_RATE/2))/PLAYBACK_RATE)

.equ ARM_SWI_CPU_FAST_SET, 0xC0000

.align 2

.type mos6581_reset, %function
.func mos6581_reset
mos6581_reset:
	str		lr,[sp,#-4]!
	ldr		r0,=mos6581_channels
	mov		r3,#0
.reset_channels:
	mov		r1,r3
	bl		mos6581_channel_set_index
	bl		mos6581_channel_reset
	add		r0,r0,#SIZEOF_CHN
	add		r3,r3,#1
	cmp		r3,#3
	bne		.reset_channels
	ldr		r0,=noiseSeed
	mov		r1,#1
	str		r1,[r0]
	ldr		lr,[sp],#4
	bx		lr
.endfunc


.type mos6581_write, %function
.func mos6581_write
@ r0 = addr
@ r1 = data
mos6581_write:
	str     r4,[sp,#-4]!
	and		r0,r0,#0x1F
	ldr		r2,=mos6581_regs
	ldr		r3,=prevRegValue
	ldrb	r4,[r2,r0]			@ r4 = regs[addr]
	strb	r4,[r3]				@ prevRegValue = regs[addr]
	strb	r1,[r2,r0]			@ regs[addr] = data

	cmp		r0,#MOS6581_R_FILTER_MODEVOL
	beq		.write_modevol
	cmp		r0,#MOS6581_R_VOICE3_SR
	@ ignore writes to the filter registers
	ldrhi   r4,[sp],#4
    movhi   pc,lr

	@ approximate addr/7
	add		r4,r0,r0,lsl#3	@ r4 = addr*9
	add		r4,r4,#2
	mov		r4,r4,lsr#6		@ 9/64 == 1/7.111
	
	@ r2 = &mos6581_channels[addr/7]
	mov		r3,#SIZEOF_CHN
	mla		r2,r4,r3,r2
	add		r2,r2,#0x20
    ldr     r4,[sp],#4
    @ Note: relies on mos6581_channel_write preserving r4
	b		mos6581_channel_write

.write_modevol:
	tst		r1,#0x80	@ r3 = (data & 0x80)
	movne	r3,#0       @    ? 0
	mvneq	r3,#0       @    : 0xFFFF
	add		r2,r2,#0x20
	strh	r3,[r2,#(SIZEOF_CHN*2 + CHN_OUTPUT_MASK)]
	ldr     r4,[sp],#4
	mov     pc,lr
.endfunc

.align 2
.pool
.align 2


.macro STEP_ENVELOPE_GENERATOR
    @ step envelope generator
    ldrb    r5,[r3,#CHN_EG_CLOCKED]
    tst     r5,r5
    beq     .eg_stepped\@         @ if (!clocked) done
    @ pos += EG_STEP
    ldr     r5,=EG_STEP
    ldr     r6,[r3,#CHN_EG_POS]
    ldr     r7,[r3,#CHN_EG_PER_SCALED]
    add     r5,r6,r5
    cmp     r5,r7
    @ if (pos < periodScaled) done
    strcc   r5,[r3,#CHN_EG_POS]
    bcc     .eg_stepped\@
    @ pos -= periodScaled
    sub     r5,r5,r7
    ldrb    r6,[r3,#CHN_EG_PHASE]
    str     r5,[r3,#CHN_EG_POS]
    ldr     r7,[pc,r6,lsl#2]
    bx      r7
.phase_lut\@:
    .word .attack_phase\@
    .word .decay_phase\@
    .word .sustain_phase\@
    .word .release_phase\@
.attack_phase\@:
    @ out++
    add     r8,r8,#1
    cmp     r8,#0xFF
    @ if (out < 0xFF) done
    bcc     .eg_stepped\@
    @ out = 0xFF; phase = DECAY; clockDivider = 1;
    mov     r8,#0xFF
    mov     r6,#EG_DECAY
    mov     r7,#1
    strb    r6,[r3,#CHN_EG_PHASE]
    strb    r7,[r3,#CHN_EG_CLK_DIV]
    @ period = periodScaled = EG_PERIODS[regs[MOS6581_R_VOICE1_AD] & 0x0F]
    ldrb    r6,[r2,#MOS6581_R_VOICE1_AD]
    ldr     r5,=_EG_PERIODS
    and     r6,r6,#0x0F
    ldr     r7,[r5,r6,lsl#2]
    str     r7,[r3,#CHN_PERIOD]
    str     r7,[r3,#CHN_EG_PER_SCALED]
    b       .eg_stepped\@
.decay_phase\@:
    ldrb    r6,[r3,#CHN_EG_SUS_LEVEL]
    @ if (out <= sustainLevel) { out = sustainLevel; clocked = false; phase = SUSTAIN; return; }
    cmp     r8,r6
    movls   r8,r6
    movls   r5,#0
    movls   r6,#EG_SUSTAIN
    strlsb  r5,[r3,#CHN_EG_CLOCKED]
    strlsb  r6,[r3,#CHN_EG_PHASE]
    bls     .eg_stepped\@
    @ if (out) out--
    tst     r8,r8
    subne   r8,r8,#1
    ldr     r6,=_EG_CLK_DIV_LUT
    ldrb    r7,[r6,r8]      @ r7 = EG_CLK_DIV_LUT[out]
    tst     r7,r7
    beq     .eg_stepped\@
    @ periodScaled = period * EG_CLK_DIV_LUT[out]
    ldr     r6,[r3,#CHN_EG_PERIOD]
    strb    r7,[r3,#CHN_EG_CLK_DIV]
    mul     r6,r7,r6
    str     r6,[r3,#CHN_EG_PER_SCALED]
    b       .eg_stepped\@
.release_phase\@:
    @ if (out) out--
    tst     r8,r8
    subnes  r8,r8,#1
    @ if (!out) clocked = false
    moveq   r6,#0
    streqb  r6,[r3,#CHN_EG_CLOCKED]
    ldr     r6,=_EG_CLK_DIV_LUT
    ldrb    r7,[r6,r8]      @ r7 = EG_CLK_DIV_LUT[out]
    tst     r7,r7
    beq     .eg_stepped\@     @ if (!EG_CLK_DIV_LUT[out]) return
    @ periodScaled = period * EG_CLK_DIV_LUT[out]
    ldr     r6,[r3,#CHN_EG_PERIOD]
    strb    r7,[r3,#CHN_EG_CLK_DIV]
    mul     r6,r7,r6
    str     r6,[r3,#CHN_EG_PER_SCALED]
.sustain_phase\@:
.eg_stepped\@:
.endm


.type mos6581_run, %function
.func mos6581_run
@ r0 = numSamples
@ r1 = buffer
mos6581_run:
    stmfd	sp!,{r4-r12,lr}

    @ Register usage:
    @----------------
    @ r2 = regs*
    @ r3 = channel*
    @ r4 = pos
    @ r5 = scratch
    @ r6 = scratch
    @ r7 = scratch
    @ r8 = eg->out
    @ r9 = step
    @ r10 = ctrl
    @ r11 = scratch

    @ clear the buffer
    stmfd	sp!,{r0,r1}
    mov		r2,#(1<<24)     @ DMA_SRC_FIXED
    orr		r2,r2,r0,lsr#2
    ldr		r0,=zero
    swi     ARM_SWI_CPU_FAST_SET
    ldmfd	sp!,{r0,r1}

    sub		sp,sp,#32       @ create space for some local variables
    mov		r2,#3
    str		r2,[sp,#8]      @ loop counter
	
    ldr		r2,=mos6581_regs
    add		r3,r2,#0x20	    @ r3 = mos6581_channels
.run_channels:
    str     r0,[sp]	        @ spill numSamples to the stack
    str     r1,[sp,#4]      @ spill buffer to the stack
    ldrb    r10,[r2,#MOS6581_R_VOICE1_CTRL]
    ldr     r4,[r3,#CHN_POS]
    ldr     r5,[r3,#CHN_NEXT_REG_BLOCK]
    ldrb    r6,[r5,#MOS6581_R_VOICE1_CTRL]
    and     r6,r6,#MOS6581_VOICE_CTRL_SYNC
    ldrb    r8,[r3,#CHN_EG_OUT]
    bic     r10,r10,#MOS6581_VOICE_CTRL_SYNC
    orr     r10,r10,r6
    tst     r10,#MOS6581_VOICE_CTRL_TEST
    movne   r9,#0
    ldreq   r9,[r3,#CHN_STEP_SCALED]

    and     r5,r10,#0xF2
    cmp     r5,#MOS6581_VOICE_CTRL_PULSE
    beq     run_samples_pulse_only
  
.run_samples:
    STEP_ENVELOPE_GENERATOR

    mov     r5,r4       @ oldPos = pos
    add     r4,r4,r9    @ pos += step

    @ hard sync
    eor     r6,r4,r5    @ r6 = pos ^ oldPos
    tst     r10,#MOS6581_VOICE_CTRL_SYNC
    beq     .no_hard_sync
    tst		r6,r4
    movmi	r7,#0
    ldrmi	r6,[r3,#CHN_NEXT_CHN]
    strmi	r7,[r6,#CHN_POS]	
.no_hard_sync:

    @ noise
    mov		r6,r6,lsr#28
    tst		r6,#0x0F
    beq		.no_noise_update
    ldr		r6,=noiseSeed
    ldr		r7,=1103515245
    ldr		r11,[r6]
    ldr		r5,=12345
    mla		r7,r11,r7,r5
    str		r7,[r6]
    mov		r7,r7,lsr#16
    and		r7,r7,#0xFF
    mov		r7,r7,lsl#4
    strh	r7,[r3,#CHN_NOISE_OUT]
.no_noise_update:

    @ pulse wave
    tst		r10,#MOS6581_VOICE_CTRL_PULSE
    ldrne	r5,=0xFFF
    ldrneh	r6,[r3,#CHN_DUTY]
    subne	r6,r5,r6
    @ pulseOut = ((chn->pos >> (12 + OSC_STEP_SHIFT)) >= (0xFFF - chn->duty)) ? 0xFFF : 0
    rsbnes	r6,r6,r4,lsr#20	
    movpl	r11,r5
    movmi	r11,#0

    mov		r5,#0		@ out

    tst		r10,#MOS6581_VOICE_CTRL_TRIANGLE
    beq		.no_triangle_out
    ldr		r7,=0xFFE
    mov		r5,r4,lsr#(11 + OSC_STEP_SHIFT)
    and		r5,r5,r7
    tst     r10,#MOS6581_VOICE_CTRL_SAW
    ldreq   r6,[r3,#CHN_PREV_CHN]
    ldreq   r6,[r6,#CHN_POS]
    andeq   r6,r6,r10,lsl#(21 + OSC_STEP_SHIFT)  @ RMOD
    eoreqs  r6,r6,r4
    eormi   r5,r5,r7
	
	tst		r10,#MOS6581_VOICE_CTRL_SAW
	andne	r5,r5,r4,lsr#(12 + OSC_STEP_SHIFT)

	tst		r10,#MOS6581_VOICE_CTRL_PULSE
	andne	r5,r5,r11
	
	@ *buffer += (out >> 14) & outputMask; buffer++
	ldrh	r6,[r3,#CHN_OUTPUT_MASK]
	sub		r5,r5,#0x800
	mul		r5,r8,r5
	ldrsb	r7,[r1]
	and		r5,r6,r5,lsr#14
	add		r7,r7,r5
	subs	r0,r0,#1
	strb	r7,[r1]
	add		r1,r1,#1
	bne		.run_samples
	b		.next_channel

.no_triangle_out:
    eor		r6,r10,#0xF0
    msr		CPSR_f,#0
    tst		r6,#MOS6581_VOICE_CTRL_SAW
    @ r5 = (ctrl & MOS6581_VOICE_CTRL_SAW) ? sawOut : pulseOut
    moveq	r5,r4,lsr#(12 + OSC_STEP_SHIFT)
    movne	r5,r11
    msrne	CPSR_f,#0x20000000		@ if (!(ctrl & MOS6581_VOICE_CTRL_SAW)) set C flag

    tst		r6,#MOS6581_VOICE_CTRL_PULSE
    @ r5 = (ctrl & MOS6581_VOICE_CTRL_PULSE) ? ((ctrl & MOS6581_VOICE_CTRL_SAW) ? (sawOut & pulseOut) : pulseOut) : ((ctrl & MOS6581_VOICE_CTRL_SAW) ? sawOut : pulseOut)
    andeq	r5,r5,r11
    mrshi	r7,CPSR
    orrhi	r7,r7,#0x10000000
    msrhi	CPSR_f,r7			@ if (!(ctrl & (MOS6581_VOICE_CTRL_PULSE | MOS6581_VOICE_CTRL_SAW))) set V flag

    @ r5 = (!(ctrl & (MOS6581_VOICE_CTRL_PULSE | MOS6581_VOICE_CTRL_SAW | MOS6581_VOICE_CTRL_NOISE))) ? 0 : r5
    tsthi   r6,#MOS6581_VOICE_CTRL_NOISE
    movhi   r5,#0
    @ if ((ctrl & MOS6581_VOICE_CTRL_NOISE) && !(ctrl & (MOS6581_VOICE_CTRL_PULSE | MOS6581_VOICE_CTRL_SAW))) r5 = noiseOut
    mrsls   r6,CPSR
    andls   r6,r6,#0x50000000
    cmp     r6,#0x50000000
    ldreqh  r5,[r3,#CHN_NOISE_OUT]

.mix:
    @ *buffer += (out >> 14) & outputMask; buffer++
    ldrh    r6,[r3,#CHN_OUTPUT_MASK]
    sub     r5,r5,#0x800
    mul 	r5,r8,r5
    ldrsb   r7,[r1]
    and 	r5,r6,r5,lsr#14
    add 	r7,r7,r5
    subs    r0,r0,#1
    strb    r7,[r1]
    add     r1,r1,#1
    bne     .run_samples

.next_channel:
    strb	r8,[r3,#CHN_EG_OUT]
    str		r4,[r3,#CHN_POS]
    add		r2,r2,#7
    add 	r3,r3,#SIZEOF_CHN
    ldrb	r1,[sp,#8]
    subs	r1,r1,#1
    strne	r1,[sp,#8]
    ldrne	r0,[sp]
    ldrne	r1,[sp,#4]
    bne		.run_channels

    add		sp,sp,#32
    ldmfd	sp!,{r4-r12,lr}
    bx		lr

@ Optimize for the case where only the pulse oscillator is used
run_samples_pulse_only:
   ldr     r10,=0xFFF
   ldrh    r6,[r3,#CHN_DUTY]
    sub     r10,r10,r6
3:    
    STEP_ENVELOPE_GENERATOR
    mov     r5,r4       @ oldPos = pos
    add     r4,r4,r9    @ pos += step
    @ noise
    eor     r6,r4,r5    @ r6 = pos ^ oldPos
    mov     r6,r6,lsr#28
    tst     r6,#0x0F
    beq     1f
    ldr     r6,=noiseSeed
    ldr     r7,=1103515245
    ldr     r11,[r6]
    ldr     r5,=12345
    mla     r7,r11,r7,r5
    str     r7,[r6]
    mov     r7,r7,lsr#16
    and     r7,r7,#0xFF
    mov     r7,r7,lsl#4
    strh    r7,[r3,#CHN_NOISE_OUT]
1:
    @ pulseOut = ((chn->pos >> (12 + OSC_STEP_SHIFT)) >= (0xFFF - chn->duty)) ? 0xFFF : 0
    rsbs    r6,r10,r4,lsr#20
    movpl   r5,#0xF00
    orrpl   r5,#0xFF
    movmi   r5,#0
  
    @ *buffer += (out >> 14) & outputMask; buffer++
    ldrh    r6,[r3,#CHN_OUTPUT_MASK]
    sub     r5,r5,#0x800
    mul     r5,r8,r5
    ldrsb   r7,[r1]
    and     r5,r6,r5,lsr#14
    add     r7,r7,r5
    subs    r0,r0,#1
    strb    r7,[r1]
    add     r1,r1,#1
    bne     3b
    b       .next_channel
    
.endfunc

.align 2
.pool



@ r0 = channel*
mos6581_channel_reset:
	mov		r1,#0
	str		r1,[r0,#CHN_PERIOD]
	str		r1,[r0,#CHN_STEP]
	str		r1,[r0,#CHN_EG_POS]
	str		r1,[r0,#CHN_EG_PHASE]
	str		r1,[r0,#CHN_EG_CLOCKED]
	strh	r1,[r0,#CHN_DUTY]
	strh	r1,[r0,#CHN_EG_OUT]
	strh	r1,[r0,#CHN_NOISE_OUT]
	ldr		r1,=0xFFFF
	str		r1,[r0,#CHN_OUTPUT_MASK]
	strh	r1,[r0,#CHN_OUT]
	ldr		r1,=0x7FFFF8
	str		r1,[r0,#CHN_LFSR]
	mov		r1,#1
	str		r1,[r0,#CHN_EG_CLK_DIV]
	mov		pc,lr
	
	
@ r0 = channel*
@ r1 = index
mos6581_channel_set_index:
	str		r1,[r0,#CHN_INDEX]
	cmp 	r1,#0
	addeq 	r2,r0,#(SIZEOF_CHN*2)
	subne 	r2,r0,#SIZEOF_CHN
	str 	r2,[r0,#CHN_PREV_CHN]
	cmp 	r1,#2
	subeq 	r2,r0,#(SIZEOF_CHN*2)
	addne 	r2,r0,#SIZEOF_CHN
	str 	r2,[r0,#CHN_NEXT_CHN]
	moveq	r2,#0
	addne	r2,r1,#1
	mov 	r1,#7
	mul 	r2,r1,r2
	ldr		r1,=mos6581_regs
	add		r2,r2,r1
	str 	r2,[r0,#CHN_NEXT_REG_BLOCK]
	mov 	pc,lr


call_calc_step_scaled:
	ldr r3,=calc_step_scaled
	bx r3
	
	
@ r0 = addr
@ r1 = data
@ r2 = channel*
mos6581_channel_write:
	cmp		r0,#MOS6581_R_VOICE3_SR
	movhi	pc,lr
	stmfd	sp!,{r4-r7}
	ldr		r3,[r2,#CHN_INDEX]
	rsb		r4,r3,r3,lsl#3		@ r4 = index*7
	ldr		r5,=mos6581_regs
	add		r4,r5,r4			@ r4 = &regs[index*7]
	ldr		r3,[pc,r0,lsl#2]
	bx		r3
.channel_write_lut:
	.rept 3
	.word 	.write_freq_lo
	.word 	.write_freq_hi
	.word 	.write_pw_lo
	.word 	.write_pw_hi
	.word 	.write_ctrl
	.word 	.write_ad
	.word 	.write_sr
	.endr
	
.write_freq_lo:
	ldrb	r3,[r4,#MOS6581_R_VOICE1_FREQ_HI]
	add		r3,r1,r3,lsl#8
.calc_step_scaled:	
	ldr		r5,=(PAL_PHI * 8 * 256 )
	umull	r6,r7,r5,r3
	str		r3,[r2,#CHN_STEP]
	mov		r6,r6,lsr#18
	orr		r6,r6,r7,lsl#14
	str		r6,[r2,#CHN_STEP_SCALED]
	ldmfd	sp!,{r4-r7}
	mov		pc,lr
.write_freq_hi:
	ldrb	r3,[r4,#MOS6581_R_VOICE1_FREQ_LO]
	add		r3,r3,r1,lsl#8
	b		.calc_step_scaled
	
.write_pw_lo:
	ldrb	r3,[r4,#MOS6581_R_VOICE1_PW_HI]
	and		r3,r3,#0xF
	add		r3,r1,r3,lsl#8
	strh	r3,[r2,#CHN_DUTY]
	ldmfd	sp!,{r4-r7}
	mov		pc,lr
.write_pw_hi:
	ldrb	r3,[r4,#MOS6581_R_VOICE1_PW_LO]
	and		r1,r1,#0xF
	add		r3,r3,r1,lsl#8
	strh	r3,[r2,#CHN_DUTY]
	ldmfd	sp!,{r4-r7}
	mov		pc,lr

.write_sr:
	ldrb	r3,[r4,#MOS6581_R_VOICE1_SR]
	mov		r3,r3,lsr#4
	orr		r3,r3,r3,lsl#4
	strh	r3,[r2,#CHN_EG_SUS_LEVEL]
.write_ad:
	ldmfd	sp!,{r4-r7}
	mov		pc,lr
	
.write_ctrl:
	ldr		r5,=prevRegValue
	ldrb	r6,[r5]
	eor		r6,r6,r1
	tst		r6,#MOS6581_VOICE_CTRL_GATE
	beq		.no_gate_bit_change
	tst		r1,#MOS6581_VOICE_CTRL_GATE
	bne		.voice_gated
	mov		r5,#1
	mov		r6,#EG_RELEASE
	strb	r5,[r2,#CHN_EG_CLOCKED]
	strb	r6,[r2,#CHN_EG_PHASE]
	ldrb	r3,[r4,#MOS6581_R_VOICE1_SR]
	ldr		r5,=_EG_PERIODS
	and		r3,r3,#0xF
	ldr		r5,[r5,r3,lsl#2]
	ldrb	r6,[r2,#CHN_EG_CLK_DIV]
	str		r5,[r2,#CHN_EG_PERIOD]
	mul		r6,r5,r6
	str		r6,[r2,#CHN_EG_PER_SCALED]
	b		.no_gate_bit_change
.voice_gated:
	mov		r5,#1
	mov		r6,#EG_ATTACK
	strb	r5,[r2,#CHN_EG_CLOCKED]
	strb	r6,[r2,#CHN_EG_PHASE]
	strb	r5,[r2,#CHN_EG_CLK_DIV]
	ldrb	r3,[r4,#MOS6581_R_VOICE1_AD]
	ldr		r5,=_EG_PERIODS
	mov		r3,r3,lsr#4
	ldr		r5,[r5,r3,lsl#2]
	str		r5,[r2,#CHN_EG_PERIOD]
	str		r5,[r2,#CHN_EG_PER_SCALED]
.no_gate_bit_change:
	tst 	r1,#MOS6581_VOICE_CTRL_TEST
	beq		.test_bit_clear
	ldr		r5,=0x7FFFF8
	str		r5,[r2,#CHN_LFSR]
	ldr		r5,=noiseSeed
	mov		r6,#1
	str		r6,[r5]
	ldr		r5,=(0xFFFFFF << OSC_STEP_SHIFT)
	str		r5,[r2,#CHN_POS]
.test_bit_clear:		
	ldmfd	sp!,{r4-r7}
	mov		pc,lr

	

.align 2
.pool


.align 2
_EG_PERIODS:
.word 9 << EG_STEP_SHIFT
.word 32 << EG_STEP_SHIFT
.word 63 << EG_STEP_SHIFT
.word 95 << EG_STEP_SHIFT
.word 149 << EG_STEP_SHIFT
.word 220 << EG_STEP_SHIFT
.word 267 << EG_STEP_SHIFT
.word 313 << EG_STEP_SHIFT
.word 392 << EG_STEP_SHIFT
.word 977 << EG_STEP_SHIFT
.word 1953 << EG_STEP_SHIFT
.word 3125 << EG_STEP_SHIFT
.word 3906 << EG_STEP_SHIFT
.word 11718 << EG_STEP_SHIFT
.word 19531 << EG_STEP_SHIFT
.word 31250 << EG_STEP_SHIFT

_EG_CLK_DIV_LUT:
.byte 0x01,0x00,0x00,0x00,0x00,0x00,0x1E,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x10,0x00
.byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x08,0x00,0x00,0x00,0x00,0x00
.byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
.byte 0x00,0x00,0x00,0x00,0x00,0x00,0x04,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
.byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
.byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x02,0x00,0x00
.byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
.byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
.byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
.byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
.byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
.byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
.byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
.byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
.byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
.byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00

.data
.align 2
noiseSeed: .word 1
zero: .word 0
prevRegValue: .byte 0


.section .bss
.align 2
.comm mos6581_regs,0x20
.comm mos6581_channels,SIZEOF_CHN*3
