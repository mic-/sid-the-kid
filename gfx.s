.global bground
.global bgnam
.global bgpal
.global font
.global font2
.global arrow

.section .rodata

.align 2
bground: .incbin "splash.bin"
.align 2
bgnam: .incbin "splash.nam"
.align 2
bgpal: .incbin "splash.pal"
.align 2
font: .incbin "Trantor.bin"
font2: .incbin "Trantor2.bin"
.align 2
arrow: .incbin "arrow.bin"
