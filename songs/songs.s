.global SONG_POINTERS
.global SONG_SIZES
.global NUM_SONGS

.section .text

.align 2

SONG1:  .incbin "songs/Aquanori.sid"
SONG2:  .incbin "songs/Austria_Party_2.sid"
SONG3:  .incbin "songs/Cartilage_2.sid"
SONG4:  .incbin "songs/Challenge.sid"
SONG5:  .incbin "songs/Constellation_of_Dragon.sid"
SONG6:  .incbin "songs/Feel_the_Time.sid"
SONG7:  .incbin "songs/good_enough.sid"
SONG8:  .incbin "songs/Kinetix.sid"
SONG9:  .incbin "songs/Nag_Champa.sid"
SONG10: .incbin "songs/Nefarious.sid"
SONG11: .incbin "songs/On_A_Rainy_Day.sid"
SONG12: .incbin "songs/Rise_and_Sine.sid"
SONG13: .incbin "songs/S2-Tune.sid"
SONG14: .incbin "songs/Shadow_of_the_Beast_demo.sid"
SONG15:  .incbin "songs/Symphony_of_Doom.sid"
SONG16: .incbin "songs/Tarzan_Goes_Ape.sid"
SONG_END:

.align 2
SONG_POINTERS:
.word SONG1
.word SONG2
.word SONG3
.word SONG4
.word SONG5
.word SONG6
.word SONG7
.word SONG8
.word SONG9
.word SONG10
.word SONG11
.word SONG12
.word SONG13
.word SONG14
.word SONG15
.word SONG16

SONG_SIZES:
.word SONG2  - SONG1
.word SONG3  - SONG2
.word SONG4  - SONG3
.word SONG5  - SONG4
.word SONG6  - SONG5
.word SONG7  - SONG6
.word SONG8  - SONG7
.word SONG9  - SONG8
.word SONG10 - SONG9
.word SONG11 - SONG10
.word SONG12 - SONG11
.word SONG13 - SONG12
.word SONG14 - SONG13
.word SONG15 - SONG14
.word SONG16 - SONG15
.word SONG_END - SONG16

NUM_SONGS:
.word (SONG_SIZES - SONG_POINTERS) / 4
