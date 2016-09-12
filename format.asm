

  [section .text align=1]
; * ----------------------------------------------
;*******
 extern file_read_all
 extern file_write_close
 extern blk_replace
; extern crt_clear
 extern crt_str
 extern blk_del_bytes
 extern blk_insert_bytes
 extern blk_find

 [section .text]

 global _start
 global main

main:
_start:
  mov	[next_write],dword outbuf
  mov	[next_read],dword inbuf
;
  mov	ebp,in_file
  mov	edx,inbuf_end - inbuf	;buffer size
  mov	ecx,inbuf
  mov	al,1			;local file
  call	file_read_all
;  js	fd_error		;jmp if failure
  add	eax,inbuf
  mov	[infile_end_ptr],eax			;move file end ptr to ebp
;
; process one input line
;
  cld
process_loop:
  mov	esi,[next_read]
  mov	edi,[next_write]

  lodsb
  cmp	al,'_'
  jne	pl_error1
  mov	ebx,del_col
  mov	ecx,3
  call	move_it

  lodsb
  cmp	al,"D"
  je	day_rcl
  cmp	al,'d'
  je	day_rcl
  cmp	al,'W'
  je	week_rcl
  cmp	al,'w'
  je	week_rcl
  cmp	al,'M'
  je	month_rcl
  cmp	al,'m'
  je	month_rcl
  cmp	al,'Y'
  je	year_rcl
  cmp	al,'y'
  je	year_rcl
pl_error1:
  jmp	pl_error2 

day_rcl:
  lodsb		;get next char
  mov	ebx,no_rcl
  cmp	al,'0'
  je	do_move
  mov	ebx,day_stuff
  mov	[ebx],al
  jmp	do_move

week_rcl:
  lodsb		;get weeks
  mov	ebx,week_stuff
  mov	[ebx],al
  jmp	do_move

month_rcl:
  lodsb
  cmp	al,'E'
  mov	ebx,eom_move
  je	do_move
  mov	ebx,month_stuff
  mov	[ebx],al
  jmp	do_move

year_rcl:
  lodsb
  mov	ebx,year_stuff
  mov	[ebx],al

do_move:
  mov	al,' '
  stosb
  mov	ecx,3
  call	move_it
  mov	al,' '
  stosb
;
; move year
;
  mov	ebx,esi
  mov	ecx,4
  call	move_it
  add	esi,4

  mov	al,'/'
  stosb

  mov	ebx,esi
  mov	ecx,2		;lenght of date
  call	move_it
  add	esi,2

  mov	al,'/'
  stosb

  mov	ebx,esi
  mov	ecx,2
  call	move_it
  add	esi,2

  mov	ebx,pri_link
  mov	ecx,7
  call	move_it
;
; move text of todo
;
text_move:
  lodsb
  stosb
  cmp	al,0ah
  jne	text_move
entry_end_ck:
  lodsb
  cmp	al,0ah
  je	line_end		;jmp if end of todo
dump_extra:
  lodsb
  cmp	al,0ah
  jne	dump_extra
  jmp	short entry_end_ck

line_end:
  mov	[next_read],esi
  mov	[next_write],edi
  cmp	esi,[infile_end_ptr]
  jae	write_file
  jmp	process_loop	  

pl_error2:
  jmp	fd_exit
;
; write file and exit
;
write_file:
  mov	eax,outbuf
  mov	ecx,[next_write] ;get file end ptr
  sub	ecx,eax		;compute length of write
  mov	ebx,out_file
  mov	esi,1
  call	file_write_close
fd_exit:
  mov	ebx,0
  mov	eax,1
  int	80h		;exit  

;----------------------------------------
; ecx=length ebx=source edi=destinaltion
move_it:
  mov	al,[ebx]
  inc	ebx
  stosb
  loop	move_it
  ret

  [section .data]

del_col		db '_?_'
no_rcl		db '   '
day_stuff	db '1da'
week_stuff	db '1wk'
month_stuff	db '1mo'
year_stuff	db '1yr'
eom_move	db 'eom'
pri_link	db 'P ____ '

in_file:	db "todo.old",0
out_file:	db "todo.new",0

  [section .bss]

next_read	resd	1	;next byte to process
infile_end_ptr	resd	1
inbuf	resb	64000
inbuf_end resb	1

next_write	resd 1
outbuf	resb	64000

 [section .text]
