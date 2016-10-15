@ C64/SID memory mapping routines for the ARM7TDMI
@ /Mic, 2016

.global sidmapper_reset
.global sidmapper_write_byte

.text
.section .iwram

.type sidmapper_reset, %function
.func sidmapper_reset
sidmapper_reset:
    ldr		r0,=C64_RAM
    mov		r1,#0x35
    strb	r1,[r0,#1]      @ RAM[1] = 0x35
    bx		lr
.endfunc

	
@ In: r0 = address
@     r1 = value
@ Needs to preserve r0, r2
.type sidmapper_write_byte, %function
.func sidmapper_write_byte
sidmapper_write_byte:
    mov		r9,r0,lsr#12
    subs	r9,r9,#0xA
    strccb	r1,[r0,r3]      @ if ((address >> 12) < 0xA) { RAM[address] = value; return }
    bxcc	lr
    ldr		r9,[pc,r9,lsl#2]
    bx		r9
.page_lut:
    .word	.write_page_a_b
    .word	.write_page_a_b
    .word	.default_write
    .word	.write_page_d
    .word	.write_page_e_f
    .word	.write_page_e_f

.write_page_a_b:
    ldrb	r9,[r3,#1]
    and		r9,r9,#3
    cmp		r9,#3           @ is ((bankSelect & 3) == 3) ? (BASIC ROM mapped to $A000-BFFF)
    bxeq	lr              @ yup. can't write to ROM; return
.default_write:
    strb	r1,[r0,r3]
    bx		lr

.write_page_d:
    ldrb	r9,[r3,#1]
    ands	r9,#7
    @ if (bankSelect == 4 || bankSelect == 0) write to RAM
    @ if (bankSelect < 4) return
    streqb	r1,[r0,r3]
    bxeq	lr
    cmp		r9,#4
    streqb	r1,[r0,r3]
    bxls	lr
    @ bankSelect > 4 => I/O mapped to $D000-DFFF
.io_at_page_d:
    cmp		r0,#0xD400
    bxcc	lr              @ if (address < 0xD400) return
    ldr		r9,=0xD7FF
    cmp		r0,r9
    bxhi	lr              @ if (address > 0xD7FF) return
    stmfd	sp!,{r0,r2-r10,r11,r12,lr}
    ldr		r9,=0xD41F
    mov		r5,r1           @ save value
    and		r0,r0,r9
    mov		r4,r0           @ save address

    bl		mos6581_write
    ldr		r9,=0xD418
    cmp		r4,r9
    ldmnefd	sp!,{r0,r2-r10,r11,r12,pc}
    and		r0,r5,#0x0F
    bl		call_set_master_volume
    ldmfd	sp!,{r0,r2-r10,r11,r12,pc}

.write_page_e_f:
    ldrb	r9,[r3,#1]
    and		r9,r9,#3
    cmp		r9,#1
    bxhi	lr
    strb	r1,[r0,r3]
    bx		lr
.endfunc


call_mos6581_write:
    ldr		r2,=mos6581_write
    bx		r2
	
call_set_master_volume:
    ldr		r2,=sidplayer_set_master_volume
    bx		r2
