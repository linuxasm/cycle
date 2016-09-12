
normal_color	equ	80000000h
bold_color	equ	40000000h
underline	equ	20000000h
blink		equ	10000000h
reverse		equ	08000000h

black_char	equ	30h	;builds 3330h
red_char	equ	31h	;builds 3331h
green_char	equ	32h
yellow_char	equ	33h
blue_char	equ	34h
magenta_char	equ	35h
cyan_char	equ	36h
white_char	equ	37h

on_black	equ	3000h	;builds '40'
on_red		equ	3100h
on_green	equ	3200h
on_yellow	equ	3300h	;builds '43'
on_blue		equ	3400h	;
on_magenta	equ	3500h
on_cyan		equ	3600h
on_white	equ	3700h


  [section .text]
  extern str_move
  extern crt_str
;---------------------------------------
;input: edx=colors
;       edi=destination
;output: edi points to zero at end of color string
;
copy_colors:
  call	build_color
  mov	esi,color_buf
  call	str_move
  ret
;---------------------------------------
; input: color codes in edx
;
show_color:
  call	build_color
  push	esi
  mov	ecx,color_buf
  call	crt_str
  pop	esi
  ret
;---------------------------------------
build_color:
  push	edi
  cld
  mov	edi,color_buf
  mov	al,1bh
  stosb
  mov	al,'['
  stosb
  push	edx
  or	edx,edx
  jns	sc_05
  mov	al,'0'
  stosb
  mov	al,';'
  stosb
sc_05:
  shl	edx,1
  jns	sc_10
  mov	al,'1'	;bold
  stosb
  mov	al,';'
  stosb
sc_10:
  shl	edx,1
  jns	sc_15
  mov	al,'4'	;underline
  stosb
  mov	al,';'
  stosb
sc_15:
  shl	edx,1
  jns	sc_20
  mov	al,'5'	;blink
  stosb
  mov	al,';'
  stosb
sc_20:
  shl	edx,1
  jns	sc_25
  mov	al,'7'	;reverse video
  stosb
  mov	al,';'
  stosb
sc_25:
  pop	edx
  or	dl,dl
  jz	sc_30
  mov	al,'3'	;char color
  stosb
  mov	al,dl
  stosb
  mov	al,';'
  stosb
sc_30:
  or	dh,dh
  jz	sc_35
  mov	al,'4'
  stosb
  mov	al,dh
  stosb
sc_35:
  cmp	byte [edi-1],';'
  jne	sc_40		;jmp if no ';' at end
  dec	edi
sc_40:
  mov	al,'m'
  stosb
  mov	al,0
  stosb
  pop	edi
  ret

 

;------------------------------------------------
  [section .data]

color_buf	times 20 db 0

msg1	db	'red char on white blinking',0ah,0
msg2	db	'normal white char on black',0ah,0
  
 [section .text]

 global	_start
_start:
  mov	edx,blink+red_char+on_white
  call	show_color
  mov	ecx,msg1
  call	crt_str
  mov	edx,normal_color+white_char+on_black
  call	show_color
  mov	ecx,msg2
  call	crt_str
  mov	eax,1
  int	80h
