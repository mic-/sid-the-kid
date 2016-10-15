@ arm_6510.s
@ A 6510 emulator for the ARM7TDMI
@ /Mic 2016

.global emu6502_run
.global emu6502_reset
.global emu6502_setBrkVector
.global regS
.global regPC
.global regF
.global regY
.global regX
.global regA
.global cpuCycles
.global savePC

.arm
.section .iwram

@ Register usage:
@ 
@  R0:  scratch register
@  R1:  scratch register
@  R2:  scratch register
@  R3:  pointer to RAM
@  R4:  return address for instructions
@  R5:  A
@  R6:  X
@  R7:  Y
@  R8:  F
@  R9:  scratch register
@  R10: PC
@  R11: S
@  R12: The last value to base NZ flag calculation on (Nvalue<<8 | Zvalue)


.equ FLAG_C, 0x01
.equ FLAG_Z, 0x02
.equ FLAG_I, 0x04
.equ FLAG_D, 0x08
.equ FLAG_B, 0x10
.equ FLAG_V, 0x40
.equ FLAG_N, 0x80

@ I currently don't keep a cycle count, as I decided that I could make better
@ use of the ARM registers for other purposes. Instead, I just let the SID's
@ INIT/PLAY routine run until it returns.
.macro ADD_CYCLES cycnum
.endm


@ The reason for using B instructions to jump to / return from
@ the instruction handlers instead of BL is to avoid the need
@ of saving and restoring LR, since many of the instruction handlers
@ will BL to some memory access routine.
.macro RETURN
	bx	r4
.endm

@ dest = RAM[address]
.macro READ_BYTE dest,address
	ldrb	\dest,[r3,\address]
.endm

@ dest = RAM[regPC++]
.macro FETCH_BYTE dest
	READ_BYTE \dest,r10
	add		r10,r10,#1
.endm

@ regPC = RAM[regPC] + (RAM[regPC+1] << 8)
.macro FETCH_ADDR
	READ_BYTE r0,r10
	add		r10,r10,#1
	READ_BYTE r10,r10
	orr 	r10,r0,r10,lsl#8
.endm

@ Set the N and Z bits in F based on the value in r12
.macro PACK_FLAGS
	bic		r8,#(FLAG_N|FLAG_Z)
	tst		r12,#0xFF
	orreq	r8,r8,#FLAG_Z
	tst		r12,#0x8000
	orrne	r8,r8,#FLAG_N
.endm

@ Set the value of r12 based on the N and Z bits in F
.macro UNPACK_FLAGS
	tst		r8,#FLAG_Z
	movne	r12,#0
	moveq	r12,#1
	tst		r8,#FLAG_N
	orrne	r12,r12,#0x8000
.endm

@ ###########################################################################################################
@ Calculate addresses
@ ###########################################################################################################

@ zp
.macro ZP_ADDR dest
	FETCH_BYTE \dest
.endm

@ zp,X
.macro ZPX_ADDR dest
	ZP_ADDR \dest
	add \dest,\dest,r6
    and \dest,\dest,#0xFF
.endm

@ zp,Y
.macro ZPY_ADDR dest
	ZP_ADDR \dest
	add 	\dest,\dest,r7
    and \dest,\dest,#0xFF
.endm

@ abs
@ dest must not be r0
.macro ABS_ADDR dest
	FETCH_BYTE r0
	FETCH_BYTE \dest
	orr 	\dest,r0,\dest,lsl#8
.endm

@ abs,X
@ dest must not be r0
.macro ABSX_ADDR dest
	ABS_ADDR \dest
	add 	\dest,\dest,r6
	mov		\dest,\dest,lsl#16
	mov		\dest,\dest,lsr#16
	@ ToDo: add an extra cycle when adding X crosses a page boundary
.endm

@ abs,Y
@ dest must not be r0
.macro ABSY_ADDR dest
	ABS_ADDR \dest
	add 	\dest,\dest,r7
	mov		\dest,\dest,lsl#16
	mov		\dest,\dest,lsr#16
	@ ToDo: add an extra cycle when adding Y crosses a page boundary
.endm
						
@ (zp,X)
@ Result in r1
.macro INDX_ADDR
    ZPX_ADDR r0
    ldrb 	r2,[r0,r3]
    add		r0,r0,#1
    and		r0,r0,#0xFF
    ldrb	r1,[r0,r3]
    orr		r1,r2,r1,lsl#8
.endm

@ (zp),Y
@ Result in r1
.macro INDY_ADDR
    ZP_ADDR r0
    READ_BYTE r2,r0
    add 	r0,r0,#1
    and 	r0,r0,#0xFF
    READ_BYTE r1,r0
    orr 	r1,r2,r1,lsl#8
    add 	r1,r1,r7
    mov		r1,r1,lsl#16
    mov		r1,r1,lsr#16
    @ ToDo: add extra cycle if adding Y makes the address cross a page boundary
.endm
						
@ ###########################################################################################################
@ Fetch operands
@ ###########################################################################################################

.macro IMM_OP dest
    FETCH_BYTE \dest
.endm

.macro ZP_OP dest
    ZP_ADDR r0
    ldrb	\dest,[r0,r3]
.endm

.macro ZPX_OP dest, temp
    ZPX_ADDR r0
    ldrb	\dest,[r0,r3]
.endm

.macro ZPY_OP dest, temp
    ZPY_ADDR \dest
    READ_BYTE \dest,\dest
.endm

.macro ABS_OP dest
    ABS_ADDR \dest
    READ_BYTE \dest,\dest
.endm

.macro ABSX_OP dest
    ABSX_ADDR \dest
    READ_BYTE \dest,\dest
.endm

.macro ABSY_OP dest
    ABSY_ADDR \dest
    READ_BYTE \dest,\dest
.endm

.macro INDX_OP dest
    INDX_ADDR
    READ_BYTE \dest,r1
.endm

.macro INDY_OP dest
    INDY_ADDR
    READ_BYTE \dest,r1
.endm

@ ###########################################################################################################

.macro ADC_A operand
    tst     r8,r8,lsr#1             @ Carry -> CPSR
    bic     r8,#(FLAG_N|FLAG_V|FLAG_Z|FLAG_C)
    adc     r0,r5,\operand          @ r0 = A + operand + Carry (== result)
    eor     r2,r5,r0                @ r2 = oldA ^ result
    eor     \operand,\operand,r5    @ operand ^= result
    orr     r8,r8,r0,lsr#8          @ F |= Carry ? FLAG_C : 0
    and     r2,r2,\operand          @ r2 = (oldA ^ result) & (operand ^ result)
    and     r5,r0,#0xFF
    and     r2,r2,#0x80
    orr     r12,r5,r5,lsl#8
    orr     r8,r8,r2,lsr#1          @ F |= ((oldA ^ result) & (operand ^ result) & 0x80) ? FLAG_V : 0
    RETURN
.endm

.macro SBC_A operand
    eor		\operand,\operand,#0xFF
    ADC_A	\operand
.endm

@ ###########################################################################################################

@ AND/ORA/EOR
.macro BITWISE_LOGIC operation,operand,cycles
    \operation	r5,r5,\operand
    ADD_CYCLES \cycles
    orr 		r12,r5,r5,lsl#8
    RETURN
.endm

@ BIT
.macro BITop val,cycles
    bic		r8,#(FLAG_N|FLAG_V|FLAG_Z)
    and 	r12,\val,r5
    orr 	r12,r12,\val,lsl#8
    and		r0,\val,#FLAG_V
    ADD_CYCLES \cycles
    orr		r8,r8,r0
    RETURN
.endm
				 
@ ###########################################################################################################

.macro ASLop val
    bic     r8,#(FLAG_N|FLAG_Z|FLAG_C)
    orr     r8,r8,\val,lsr#7    @ F |= (val & 0x80) ? FLAG_C : 0
    mov     \val,\val,lsl#1
    and     \val,\val,#0xFF     @ val = (val << 1) & 0xFF
    orr     r12,\val,\val,lsl#8
.endm

.macro LSRop val
    bic		r8,#(FLAG_N|FLAG_Z|FLAG_C)
    movs	\val,\val,lsr#1     @ val >>= 1
    orrcs	r8,r8,#FLAG_C       @ F |= Carry ? FLAG_C : 0
  	orr 	r12,\val,\val,lsl#8	
.endm

.macro ROLop val
    tst     r8,r8,lsr#1         @ Carry -> CPSR
    bic     r8,#(FLAG_N|FLAG_Z|FLAG_C)
    adc     \val,\val,\val      @ val = (val << 1) | C
    orr     r8,r8,\val,lsr#8    @ F |= (val & 0x100) ? FLAG_C : 0
    and     \val,\val,#0xFF
    orr     r12,\val,\val,lsl#8
.endm

.macro RORop val
    orr		\val,\val,r8,lsl#8  @ val |= Carry ? 0x100 : 0
    bic		r8,#(FLAG_N|FLAG_Z|FLAG_C)
    movs	\val,\val,lsr#1     @ val >>= 1
    orrcs	r8,r8,#FLAG_C       @ F |= Carry ? FLAG_C : 0
    and		\val,\val,#0xFF
    orr 	r12,\val,\val,lsl#8
.endm

@ ###########################################################################################################
	             
.macro LDreg reg,cycles
    ADD_CYCLES \cycles
    orr     r12,\reg,\reg,lsl#8
    RETURN
.endm

.macro UPDATE_NZ val
    orr r12,\val,\val,lsl#8
.endm

@ operand in r1
.macro CMPreg reg
    bic		r8,#(FLAG_N|FLAG_Z|FLAG_C)
    subs    r12,\reg,r1
    orrcs	r8,r8,#FLAG_C
    and     r12,r12,#0xFF	
    orr     r12,r12,r12,lsl#8
.endm

@ ###########################################################################################################

.macro COND_BRANCH_SET
    addeq	r10,r10,#1
    bxeq	r4
    ldrsb	r1,[r10,r3]
    add		r10,r10,#1
    add		r10,r1,r10
    RETURN
.endm

.macro COND_BRANCH_CLEAR
    addne	r10,r10,#1
    bxne	r4
    ldrsb	r1,[r10,r3]
    add		r10,r10,#1
    add		r10,r1,r10
    RETURN
.endm
                                  
@ ###########################################################################################################

@ value in r1
.macro PUSHB
    add		r0,r11,#0x100
    strb	r1,[r3,r0]
    sub		r11,r11,#1
.endm

@ value in r1
.macro PUSHW
    mov     r2,r1,lsr#8
    add     r0,r11,#0x100
    strb    r2,[r3,r0]
    sub     r11,r11,#2
    sub     r0,r0,#1
    strb    r1,[r3,r0]
.endm
	               
.macro PULLB dest
    add		r11,r11,#1
    add		r9,r11,#0x100
    READ_BYTE \dest,r9
.endm


@ ###########################################################################################################

.type emu6502_run, %function
.func emu6502_run
emu6502_run:
    stmfd   sp!,{r4-r12,lr}
    str     r0,[sp,#-4]!    @ maxCycles

    ldr     r4,=cpu_execute_loop
    ldr     r1,=regA
    ldmia   r1,{r5-r8,r10-r12}
    ldr     r3,=C64_RAM
	
cpu_execute_loop:
    FETCH_BYTE r1
    ldr     r9,[pc,r1,lsl#2]
    bx      r9
opcode_table:
	.word op_00,op_01,op_02,op_03,op_04,op_05,op_06,op_07
	.word op_08,op_09,op_0A,op_0B,op_0C,op_0D,op_0E,op_0F
	.word op_10,op_11,op_12,op_13,op_14,op_15,op_16,op_17
	.word op_18,op_19,op_1A,op_1B,op_1C,op_1D,op_1E,op_1F
	.word op_20,op_21,op_22,op_23,op_24,op_25,op_26,op_27
	.word op_28,op_29,op_2A,op_2B,op_2C,op_2D,op_2E,op_2F
	.word op_30,op_31,op_32,op_33,op_34,op_35,op_36,op_37
	.word op_38,op_39,op_3A,op_3B,op_3C,op_3D,op_3E,op_3F
	.word op_40,op_41,op_42,op_43,op_44,op_45,op_46,op_47
	.word op_48,op_49,op_4A,op_4B,op_4C,op_4D,op_4E,op_4F
	.word op_50,op_51,op_52,op_53,op_54,op_55,op_56,op_57
	.word op_58,op_59,op_5A,op_5B,op_5C,op_5D,op_5E,op_5F
	.word op_60,op_61,op_62,op_63,op_64,op_65,op_66,op_67
	.word op_68,op_69,op_6A,op_6B,op_6C,op_6D,op_6E,op_6F
	.word op_70,op_71,op_72,op_73,op_74,op_75,op_76,op_77
	.word op_78,op_79,op_7A,op_7B,op_7C,op_7D,op_7E,op_7F
	.word op_80,op_81,op_82,op_83,op_84,op_85,op_86,op_87
	.word op_88,op_89,op_8A,op_8B,op_8C,op_8D,op_8E,op_8F
	.word op_90,op_91,op_92,op_93,op_94,op_95,op_96,op_97
	.word op_98,op_99,op_9A,op_9B,op_9C,op_9D,op_9E,op_9F
	.word op_A0,op_A1,op_A2,op_A3,op_A4,op_A5,op_A6,op_A7
	.word op_A8,op_A9,op_AA,op_AB,op_AC,op_AD,op_AE,op_AF
	.word op_B0,op_B1,op_B2,op_B3,op_B4,op_B5,op_B6,op_B7
	.word op_B8,op_B9,op_BA,op_BB,op_BC,op_BD,op_BE,op_BF
	.word op_C0,op_C1,op_C2,op_C3,op_C4,op_C5,op_C6,op_C7
	.word op_C8,op_C9,op_CA,op_CB,op_CC,op_CD,op_CE,op_CF
	.word op_D0,op_D1,op_D2,op_D3,op_D4,op_D5,op_D6,op_D7
	.word op_D8,op_D9,op_DA,op_DB,op_DC,op_DD,op_DE,op_DF
	.word op_E0,op_E1,op_E2,op_E3,op_E4,op_E5,op_E6,op_E7
	.word op_E8,op_E9,op_EA,op_EB,op_EC,op_ED,op_EE,op_EF
	.word op_F0,op_F1,op_F2,op_F3,op_F4,op_F5,op_F6,op_F7
	.word op_F8,op_F9,op_FA,op_FB,op_FC,op_FD,op_FE,op_FF	
ce_done:
	ldr		r1,=regA
	stmia	r1,{r5-r8,r10-r12}
	
	add		sp,sp,#4		@ discard stacked maxCycles
	ldmfd	sp!,{r4-r12,lr}
	bx		lr
.pool

.endfunc


.type emu6502_setBrkVector, %function
.func emu6502_setBrkVector
emu6502_setBrkVector:
    ldr		r1,=brkVector
    str		r0,[r1]
    bx		lr
.pool
.endfunc


.type emu6502_reset, %function
.func emu6502_reset
emu6502_reset:
    ldr		r1,=brkVector
    ldr		r0,=0xFFFE
    str		r0,[r1]		@ brkVector = 0xFFFE
    ldr		r1,=regF
    mov		r0,#0		@ clear flags
    str		r0,[r1]
    bx		lr
.pool
.endfunc


@ == ADC ==

op_69:		@ ADC imm
    IMM_OP r1
    ADD_CYCLES 2
    ADC_A r1

op_65:		@ ADC zp
    ZP_OP r1
    ADD_CYCLES 3
    ADC_A r1

op_75:		@ ADC zp,X
    ZPX_OP r1
    ADD_CYCLES 4
    ADC_A r1

op_6D:		@ ADC abs
    ABS_OP r1
    ADD_CYCLES 4
    ADC_A r1

op_7D:		@ ADC abs,X
	ABSX_OP r1
	ADD_CYCLES 4
	ADC_A r1

op_79:		@ ADC abs,Y
	ABSY_OP r1
	ADD_CYCLES 4
	ADC_A r1
			
op_61:		@ ADC (zp,X)
	INDX_OP r1
	ADD_CYCLES 6
	ADC_A r1

op_71:		@ ADC (zp),Y
	INDY_OP r1
	ADD_CYCLES 5
	ADC_A r1
			

@ == AND ==
op_29:		@ AND imm
	IMM_OP r1
	BITWISE_LOGIC and,r1,2

op_25:		@ AND zp
	ZP_OP r1
	BITWISE_LOGIC and,r1,3

op_35:		@ AND zp,X
	ZPX_OP r1
	BITWISE_LOGIC and,r1,4

op_2D:		@ AND abs
	ABS_OP r1
	BITWISE_LOGIC and,r1,4

op_3D:		@ AND abs,X
	ABSX_OP r1
	BITWISE_LOGIC and,r1,4

op_39:		@ AND abs,Y
	ABSY_OP r1
	BITWISE_LOGIC and,r1,4

op_21:		@ AND (zp,X)
	INDX_OP r1
	BITWISE_LOGIC and,r1,6

op_31:		@ AND (zp),Y
	INDY_OP	r1
	BITWISE_LOGIC and,r1,5

@ == ASL ==
op_0A:		@ ASL A
	ASLop r5
	ADD_CYCLES 2
	RETURN

op_06:		@ ASL zp
	ZP_ADDR r9
	READ_BYTE r1,r9
	ASLop r1
	strb r1,[r3,r9]
	ADD_CYCLES 5
	RETURN

op_16:		@ ASL zp,X
	ZPX_ADDR r9
	READ_BYTE r1,r9
	ASLop r1
	strb r1,[r3,r9]
	ADD_CYCLES 5
	RETURN

op_0E:		@ ASL abs
	@ ToDo: could load the address into r9?
	ABS_ADDR r1
	READ_BYTE r9,r1
	ASLop 	r9
	mov	r0,r1
	mov	r1,r9
	bl	sidmapper_write_byte
	ADD_CYCLES 6
	RETURN

op_1E:		@ ASL abs,X
	@ ToDo: could load the address into r9?
	ABSX_ADDR r1
	READ_BYTE r9,r1
	ASLop 	r9
	mov	r0,r1
	mov	r1,r9
	bl	sidmapper_write_byte
	ADD_CYCLES 6
	RETURN


@ == Bxx ==
op_10:		@ BPL rel
	tst		r12,#0x8000
	COND_BRANCH_CLEAR
	
op_30:		@ BMI rel
	tst		r12,#0x8000
	COND_BRANCH_SET

op_50:		@ BVC rel
	tst		r8,#FLAG_V
	COND_BRANCH_CLEAR

op_70:		@ BVS rel
	tst		r8,#FLAG_V
	COND_BRANCH_SET

op_90:		@ BCC rel
	tst		r8,#FLAG_C
	COND_BRANCH_CLEAR

op_B0:		@ BCS rel
	tst		r8,#FLAG_C
	COND_BRANCH_SET

op_D0:		@ BNE rel
	tst		r12,#0xFF
	COND_BRANCH_SET

op_F0:		@ BEQ rel
	tst		r12,#0xFF
	COND_BRANCH_CLEAR
			

@ == BIT ==
op_24:		@ BIT zp
	ZP_OP r1
	BITop r1,3

op_2C:		@ BIT abs
	ABS_OP r1
	BITop r1,4
	
@ ====
op_00:		@ BRK
	add		r10,r10,#1
	mov		r1,r10,lsl#16
	mov		r1,r1,lsr#16
	PUSHW
	PACK_FLAGS
	orr		r1,r8,#0x30
	PUSHB
	orr		r8,r8,#(FLAG_B|FLAG_I)
	ldr		r0,=brkVector
	ldr		r10,[r0]
	FETCH_ADDR
	ADD_CYCLES 7
	RETURN

.align 2
.pool
.align 2
			
@ == CLx ==

op_18:		@ CLC
	bic	r8,#FLAG_C
	ADD_CYCLES 2
	RETURN	

op_D8:		@ CLD
	bic	r8,#FLAG_D
	ADD_CYCLES 2
	RETURN	

op_58:		@ CLI
	bic	r8,#FLAG_I
	ADD_CYCLES 2
	RETURN	

op_B8:		@ CLV
	bic	r8,#FLAG_V
	ADD_CYCLES 2
	RETURN	


@ == CMP ==
op_C9:		@ CMP imm
	IMM_OP r1
	CMPreg r5
	ADD_CYCLES 2
	RETURN

op_C5:		@ CMP zp
	ZP_OP r1
	CMPreg r5
	ADD_CYCLES 3
	RETURN

op_D5:		@ CMP zp,X
	ZPX_OP r1
	CMPreg r5
	ADD_CYCLES 4
	RETURN

op_CD:		@ CMP abs
	ABS_OP r1
	CMPreg r5
	ADD_CYCLES 4
	RETURN

op_DD:		@ CMP abs,X
	ABSX_OP r1
	CMPreg r5
	ADD_CYCLES 4
	RETURN

op_D9:		@ CMP abs,Y
	ABSY_OP r1
	CMPreg r5
	ADD_CYCLES 4
	RETURN

op_C1:		@ CMP (zp,X)
	INDX_OP r1
	CMPreg r5
	ADD_CYCLES 6
	RETURN

op_D1:		@ CMP (zp),Y
	INDY_OP r1
	CMPreg r5
	ADD_CYCLES 5
	RETURN
			

@ == CPX ==
op_E0:		@ CPX imm
	IMM_OP r1
	CMPreg r6
	ADD_CYCLES 2
	RETURN

op_E4:		@ CPX zp
	ZP_OP r1
	CMPreg r6
	ADD_CYCLES 3
	RETURN

op_EC:		@ CPX abs
	ABS_OP r1
	CMPreg r6
	ADD_CYCLES 4
	RETURN

@ == CPY ==
op_C0:		@ CPY imm
	IMM_OP r1
	CMPreg r7
	ADD_CYCLES 2
	RETURN

op_C4:		@ CPY zp
	ZP_OP r1
	CMPreg r7
	ADD_CYCLES 3
	RETURN

op_CC:		@ CPY abs
	ABS_OP r1
	CMPreg r7
	ADD_CYCLES 4
	RETURN
			
			
@ == DEC ==
op_C6:		@ DEC zp
	ZP_ADDR r9
	READ_BYTE r1,r9
	sub	r1,r1,#1
	UPDATE_NZ r1
	strb r1,[r3,r9]
	ADD_CYCLES 5
	RETURN
	
op_D6:		@ DEC zp,X
	ZPX_ADDR r9
	READ_BYTE r1,r9
	sub	r1,r1,#1
	UPDATE_NZ r1
	strb r1,[r3,r9]
	ADD_CYCLES 6
	RETURN

op_CE:		@ DEC abs
	ABS_ADDR r9
	READ_BYTE r1,r9
	sub		r1,r1,#1
	UPDATE_NZ r1
	mov		r0,r9
	bl		sidmapper_write_byte
	ADD_CYCLES 6
	RETURN

op_DE:		@ DEC abs,X
	ABSX_ADDR r9
	READ_BYTE r1,r9
	sub		r1,r1,#1
	UPDATE_NZ r1
	mov		r0,r9
	bl		sidmapper_write_byte
	ADD_CYCLES 6
	RETURN


@ ====
op_CA:		@ DEX
	subs	r6,r6,#1
	andmi	r6,r6,#0xFF
	LDreg	r6,2

op_88:		@ DEY
	subs	r7,r7,#1
	andmi	r7,r7,#0xFF
	LDreg	r7,2
	
@ == EOR ==
op_49:		@ EOR imm
	IMM_OP r1
	BITWISE_LOGIC eor,r1,2

op_45:		@ EOR zp
	ZP_OP r1
	BITWISE_LOGIC eor,r1,3

op_55:		@ EOR zp,X
	ZPX_OP r1
	BITWISE_LOGIC eor,r1,4

op_4D:		@ EOR abs
	ABS_OP r1
	BITWISE_LOGIC eor,r1,4

op_5D:		@ EOR abs,X
	ABSX_OP r1
	BITWISE_LOGIC eor,r1,4

op_59:		@ EOR abs,Y
	ABSY_OP r1
	BITWISE_LOGIC eor,r1,4

op_41:		@ EOR (zp,X)
	INDX_OP r1
	BITWISE_LOGIC eor,r1,6

op_51:		@ EOR (zp),Y
	INDY_OP r1
	BITWISE_LOGIC eor,r1,5
			

@ == INC ==
op_E6:		@ INC zp
	ZP_ADDR r9
	READ_BYTE r1,r9
	add r1,r1,#1
	UPDATE_NZ r1
	strb r1,[r3,r9]
	ADD_CYCLES 5
	RETURN
	
op_F6:		@ INC zp,X
	ZPX_ADDR r9
	READ_BYTE r1,r9
	add	r1,r1,#1
	UPDATE_NZ r1
	strb r1,[r3,r9]
	ADD_CYCLES 6
	RETURN
	
op_EE:		@ INC abs
	ABS_ADDR r9
	READ_BYTE r1,r9
	add	r1,r1,#1
	UPDATE_NZ r1
	mov	r0,r9
	bl	sidmapper_write_byte
	ADD_CYCLES 6
	RETURN
	
op_FE:		@ INC abs,X
	ABSX_ADDR r9
	READ_BYTE r1,r9
	add	r1,r1,#1
	UPDATE_NZ r1
	mov	r0,r9
	bl	sidmapper_write_byte
	ADD_CYCLES 6
	RETURN
	
			
@ ====
op_E8:		@ INX
	add		r6,r6,#1
	and		r6,r6,#0xFF
	LDreg	r6,2

op_C8:		@ INY
	add		r7,r7,#1
	and		r7,r7,#0xFF
	LDreg	r7,2
			

@ ====
op_4C:		@ JMP abs
	sub		r2,r10,#1
	FETCH_ADDR
	ADD_CYCLES 3
	cmp		r10,r2
	beq		ce_done
	RETURN


op_6C:		@ JMP (abs)
	ABS_ADDR r1
	READ_BYTE r2,r1
	add		r0,r1,#1
	and		r1,r1,#0xFF00
	and		r0,r0,#0xFF
	mov		r10,r2
	orr		r1,r1,r0
	READ_BYTE r2,r1
	orr		r10,r10,r2,lsl#8
	ADD_CYCLES 5
	RETURN
			
op_20:		@ JSR abs
	add		r1,r10,#1
	FETCH_ADDR
	PUSHW	@ push address of next instruction
	ADD_CYCLES 6
	RETURN

			
@ == LAX ==
op_A7:		@ LAX zp
	ZP_OP 	r5
	mov		r6,r5
	LDreg 	r5,3

op_B7:		@ LAX zp,Y
	ZPY_OP 	r5
	mov		r6,r5
	LDreg 	r5,4

op_AF:		@ LAX abs
	ABS_OP 	r5
	mov		r6,r5
	LDreg 	r5,4

op_BF:		@ LAX abs,Y
	ABSY_OP	r5
	mov		r6,r5
	LDreg	r5,4

op_B3:		@ LAX (zp),Y
	INDY_OP	r5
	mov		r6,r5
	LDreg	r5,5

			
@ == LDA ==
op_A9:		@ LDA imm
	IMM_OP r5
	LDreg r5,2

op_A5:		@ LDA zp
	ZP_OP r5
	LDreg r5,3

op_B5:		@ LDA zp,X
	ZPX_OP r5
	LDreg r5,4

op_AD:		@ LDA abs
	ABS_OP r5
	LDreg r5,4

op_BD:		@ LDA abs,X
	ABSX_OP r5
	LDreg r5,4
			
op_B9:		@ LDA abs,Y
	ABSY_OP r5
	LDreg r5,4

op_A1:		@ LDA (zp,X)
	INDX_OP r5
	LDreg r5,6

op_B1:		@ LDA (zp),Y
	INDY_OP r5
	LDreg r5,5


@ == LDX ==
op_A2:		@ LDX imm
	IMM_OP r6
	LDreg r6,2

op_A6:		@ LDX zp
	ZP_OP r6
	LDreg r6,3

op_B6:		@ LDX zp,Y
	ZPY_OP r6
	LDreg r6,4

op_AE:		@ LDX abs
	ABS_OP r6
	LDreg r6,4
	
op_BE:		@ LDX abs,Y
	ABSY_OP r6
	LDreg r6,4
		

@ == LDY ==
op_A0:		@ LDY imm
	IMM_OP r7
	LDreg r7,2

op_A4:		@ LDY zp
	ZP_OP r7
	LDreg r7,3

op_B4:		@ LDY zp,X
	ZPX_OP r7
	LDreg r7,4

op_AC:		@ LDY abs
	ABS_OP r7
	LDreg r7,4

op_BC:		@ LDY abs,X
	ABSX_OP r7
	LDreg r7,4	


@ == LSR ==
op_4A:		@ LSR A
	LSRop r5
	ADD_CYCLES 2
	RETURN

op_46:		@ LSR zp
	ZP_ADDR r9
	READ_BYTE r1,r9
	LSRop 	r1
	strb 	r1,[r3,r9]
	ADD_CYCLES 5
	RETURN

op_56:		@ LSR zp,X
	ZPX_ADDR r9
	READ_BYTE r1,r9
	LSRop 	r1
	strb 	r1,[r3,r9]
	ADD_CYCLES 6
	RETURN

op_4E:		@ LSR abs
	@ ToDo: could load the address into r9?
	ABS_ADDR r1
	READ_BYTE r9,r1
	LSRop 	r9
	mov		r0,r1
	mov		r1,r9
	bl		sidmapper_write_byte
	ADD_CYCLES 6
	RETURN

op_5E:		@ LSR abs,X
	@ ToDo: could load the address into r9?
	ABSX_ADDR r1
	READ_BYTE r9,r1
	LSRop 	r9
	mov		r0,r1
	mov		r1,r9
	bl		sidmapper_write_byte
	ADD_CYCLES 7
	RETURN


@ == NOP ==
op_EA:		@ NOP
op_1A:
op_3A:
op_5A:
op_7A:
op_DA:
	ADD_CYCLES 2
	RETURN


@ == ORA ==
op_09:		@ ORA imm
	IMM_OP r1
	BITWISE_LOGIC orr,r1,2

op_05:		@ ORA zp
	ZP_OP r1
	BITWISE_LOGIC orr,r1,3

op_15:		@ ORA zp,X
	ZPX_OP r1
	BITWISE_LOGIC orr,r1,4

op_0D:		@ ORA abs
	ABS_OP r1
	BITWISE_LOGIC orr,r1,4

op_1D:		@ ORA abs,X
	ABSX_OP r1
	BITWISE_LOGIC orr,r1,4

op_19:		@ ORA abs,Y
	ABSY_OP r1
	BITWISE_LOGIC orr,r1,4

op_01:		@ ORA (zp,X)
	INDX_OP r1
	BITWISE_LOGIC orr,r1,6

op_11:		@ ORA (zp),Y
	INDY_OP r1
	BITWISE_LOGIC orr,r1,5
			

@ == PHx ==
op_48:		@ PHA
	mov		r1,r5
	PUSHB
	ADD_CYCLES 3
	RETURN

op_08:		@ PHP
	PACK_FLAGS
	mov		r1,r8
	PUSHB
	ADD_CYCLES 3
	RETURN

			
@ == PLx ==
op_68:		@ PLA
	PULLB r5
	LDreg r5,4

op_28:		@ PLP
	PULLB r8
	UNPACK_FLAGS
	ADD_CYCLES 4
	RETURN
			

@ == ROL ==
op_2A:		@ ROL A
	ROLop r5
	ADD_CYCLES 2
	RETURN

op_26:		@ ROL zp
	ZP_ADDR r9
	READ_BYTE r1,r9
	ROLop 	r1
	strb 	r1,[r3,r9]
	ADD_CYCLES 5
	RETURN

op_36:		@ ROL zp,X
	ZPX_ADDR r9
	READ_BYTE r1,r9
	ROLop 	r1
	strb 	r1,[r3,r9]
	ADD_CYCLES 6
	RETURN

op_2E:		@ ROL abs
	@ ToDo: could load the address into r9?
	ABS_ADDR r1
	READ_BYTE r9,r1
	ROLop 	r9
	mov		r0,r1
	mov		r1,r9
	bl		sidmapper_write_byte
	ADD_CYCLES 6
	RETURN

op_3E:		@ ROL abs,X
	@ ToDo: could load the address into r9?
	ABSX_ADDR r1
	READ_BYTE r9,r1
	ROLop 	r9
	mov		r0,r1
	mov		r1,r9
	bl		sidmapper_write_byte
	ADD_CYCLES 7
	RETURN


@ == ROR ==
op_6A:		@ ROR A
	RORop r5
	ADD_CYCLES 2
	RETURN

op_66:		@ ROR zp
	ZP_ADDR r9
	READ_BYTE r1,r9
	RORop 	r1
	strb 	r1,[r3,r9]
	ADD_CYCLES 5
	RETURN

op_76:		@ ROR zp,X
	ZPX_ADDR r9
	READ_BYTE r1,r9
	RORop 	r1
	strb 	r1,[r3,r9]
	ADD_CYCLES 6
	RETURN
	
op_6E:		@ ROR abs
	@ ToDo: could load the address into r9?
	ABS_ADDR r1
	READ_BYTE r9,r1
	RORop 	r9
	mov		r0,r1
	mov		r1,r9
	bl		sidmapper_write_byte
	ADD_CYCLES 6
	RETURN
	
op_7E:		@ ROR abs,X
	@ ToDo: could load the address into r9?
	ABSX_ADDR r1
	READ_BYTE r9,r1
	RORop 	r9
	mov		r0,r1
	mov		r1,r9
	bl		sidmapper_write_byte
	ADD_CYCLES 7
	RETURN
	
			
@ ====
op_40:		@ RTI
	PULLB 	r8
	UNPACK_FLAGS
	PULLB 	r10
	PULLB 	r2
	orr		r10,r10,r2,lsl#8
	ADD_CYCLES 6
	RETURN

op_60:		@ RTS
	PULLB 	r10
	PULLB 	r2
	orr		r10,r10,r2,lsl#8
	add		r10,r10,#1
	ADD_CYCLES 6
	RETURN
			
			
@ == SBC ==
op_E9:		@ SBC imm
	IMM_OP r1
	ADD_CYCLES 2
	SBC_A r1
	
op_E5:		@ SBC zp
	ZP_OP r1
	ADD_CYCLES 3
	SBC_A r1

op_F5:		@ SBC zp,X
	ZPX_OP r1
	ADD_CYCLES 4
	SBC_A r1

op_ED:		@ SBC abs
	ABS_OP r1
	ADD_CYCLES 4
	SBC_A r1
			
op_FD:		@ SBC abs,X
	ABSX_OP r1
	ADD_CYCLES 4
	SBC_A r1

op_F9:		@ SBC abs,Y
	ABSY_OP r1
	ADD_CYCLES 4
	SBC_A r1

op_E1:		@ SBC (zp,X)
	INDX_OP r1
	ADD_CYCLES 6
	SBC_A r1

op_F1:		@ SBC (zp),Y
	INDY_OP r1
	ADD_CYCLES 5
	SBC_A r1
			
			
@ == SEx ==
op_38:		@ SEC
	orr		r8,r8,#FLAG_C
	ADD_CYCLES 2
	RETURN

op_F8:		@ SED
	orr		r8,r8,#FLAG_D
	ADD_CYCLES 2
	RETURN

op_78:		@ SEI
	orr		r8,r8,#FLAG_I
	ADD_CYCLES 2
	RETURN


@ == STA ==
op_85:		@ STA zp
	ZP_ADDR	r0
	strb r5,[r3,r0]
	ADD_CYCLES 3
	RETURN
	
op_95:		@ STA zp,X
	ZPX_ADDR r0
	strb r5,[r3,r0]
	ADD_CYCLES 4
	RETURN

op_8D:		@ STA abs
	ABS_ADDR r2
	mov		r0,r2
	mov		r1,r5
	bl		sidmapper_write_byte
	ADD_CYCLES 4
	RETURN

op_9D:		@ STA abs,X
	ABSX_ADDR r2
	mov		r0,r2
	mov		r1,r5
	bl		sidmapper_write_byte
	ADD_CYCLES 4
	RETURN

op_99:		@ STA abs,Y
	ABSY_ADDR r2
	mov		r0,r2
	mov		r1,r5
	bl		sidmapper_write_byte
	ADD_CYCLES 4
	RETURN

op_81:		@ STA (zp,X)
	INDX_ADDR
	mov		r0,r1
	mov		r1,r5
	bl		sidmapper_write_byte
	ADD_CYCLES 6
	RETURN

op_91:		@ STA (zp),Y
	INDY_ADDR
	mov		r0,r1
	mov		r1,r5
	bl		sidmapper_write_byte
	ADD_CYCLES 5
	RETURN
			

@ == STX ==
op_86:		@ STX zp
	ZP_ADDR	r0
	strb r6,[r3,r0]
	ADD_CYCLES 3
	RETURN

op_96:		@ STX zp,Y
	ZPY_ADDR r0
	strb r6,[r3,r0]
	ADD_CYCLES 4
	RETURN

op_8E:		@ STX abs
	ABS_ADDR r2
	mov		r0,r2
	mov		r1,r6
	bl		sidmapper_write_byte
	ADD_CYCLES 4
	RETURN
	
	
@ == STY ==
op_84:		@ STY zp
	ZP_ADDR	r0
	strb r7,[r3,r0]
	ADD_CYCLES 3
	RETURN

op_94:		@ STY zp,X
	ZPX_ADDR r0
	strb r7,[r3,r0]
	ADD_CYCLES 4
	RETURN

op_8C:		@ STY abs
	ABS_ADDR r2
	mov		r0,r2
	mov		r1,r7
	bl		sidmapper_write_byte
	ADD_CYCLES 4
	RETURN
	
	
@ == Txx ==
op_AA:		@ TAX
	mov		r6,r5
	LDreg 	r6,2

op_A8:		@ TAY
	mov 	r7,r5
	LDreg 	r7,2

op_BA:		@ TSX
	mov		r6,r11
	LDreg 	r6,2

op_8A:		@ TXA
	mov		r5,r6
	LDreg	r5,2

op_9A:		@ TXS
	mov		r11,r6
	ADD_CYCLES 2
	RETURN

op_98:		@ TYA
	mov		r5,r7
	LDreg	r5,2
	
	
@ === Illegal/undocumented opcodes

op_02: op_03: op_04: op_07: op_0B: op_0C: op_0F:
op_12: op_13: op_14: op_17: op_1B: op_1C: op_1F:
op_22: op_23: op_27: op_2B: op_2F:
op_32: op_33: op_34: op_37: op_3B: op_3C: op_3F:
op_42: op_43: op_44: op_47: op_4B: op_4F:
op_52: op_53: op_54: op_57: op_5B: op_5C: op_5F:
op_62: op_63: op_64: op_67: op_6B: op_6F:
op_72: op_73: op_74: op_77: op_7B: op_7C: op_7F:
op_80: op_82: op_83: op_87: op_89: op_8B: op_8F:
op_92: op_93: op_97: op_9B: op_9C: op_9E: op_9F:
op_A3: op_AB:
op_B2: op_BB: 
op_C2: op_C3: op_C7: op_CB: op_CF:
op_D2: op_D3: op_D4: op_D7: op_DB: op_DC: op_DF:
op_E2: op_E3: op_E7: op_EB: op_EF:
op_F2: op_F3: op_F4: op_F7: op_FA: op_FB: op_FC: op_FF:

	b op_02
	
@ ###########################################################################################################
			

.data
.align 2
regA: .long 0
regX: .long 0
regY: .long 0
regF: .long 0
regPC: .long 0
regS: .long 0
nzData: .long 1
cpuCycles: .long 0
brkVector: .long 0
cpu_max_cycles: .long 0
savePC: .long 0,0,0,0,0,0