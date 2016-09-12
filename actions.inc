; main_loop_flag
;winch_state	equ	0
;display_all_state equ	1
;display_body_state equ	2
;ignore_state	equ	3
;exit_state	equ	4
;abort_state	equ	5

  [section .text]

;--------------------------------------------------------
escape_key:
  mov	[main_loop_flag],byte exit_state
  ret
;--------------------------------------------------------
;inputs: index_ptr_curr_page
;        index_buf
;        term_rows
page_down:
  mov	eax,[term_rows]
  dec	eax
  dec	eax		;remove header & menu line
  dec	eax
  shl	eax,2		;multiply by 4
  add	eax,[index_ptr_curr_page]
  cmp	[eax],dword 0		;does data exist?
  je	pd_exit		;exit if no data on page
  mov	[index_ptr_curr_page],eax
  mov	[index_ptr_selected],eax
pd_exit:
  mov	[main_loop_flag],byte display_body_state
  ret
;--------------------------------------------------------
page_up:
  mov	eax,[index_ptr_curr_page]
  mov	ebx,[term_rows]
  dec	ebx
  dec	ebx			;remove header & menu line
  dec	ebx
  shl	ebx,2
  sub	eax,ebx			;move up one page
  cmp	eax,index_buf		;at top?
  jae	pu_exit			;jmp if pgdn ok
  mov	eax,index_buf		;force top
pu_exit:
  mov	[index_ptr_curr_page],eax
  mov	[index_ptr_selected],eax
  mov	[main_loop_flag],byte display_body_state
  ret
  
;--------------------------------------------------------
up_key:
  mov	eax,[index_ptr_selected]
  sub	eax,4
  cmp	eax,[index_ptr_curr_page]
  jae	up_exit1
;we have moved into next page
  cmp	eax,index_buf		;top of buffer?
  jb	up_exit2		;jmp if can't page up
  mov	[index_ptr_curr_page],eax ;move page up one line
up_exit1:
  mov	[index_ptr_selected],eax
up_exit2:
  mov	[main_loop_flag],byte display_body_state
  ret
;--------------------------------------------------------
down_key:
  mov	eax,[index_ptr_selected]
  add	eax,4
  cmp	[eax],dword 0		;data here?
  je	dk_exit2	;jmp if not data,can't move
;check if at bottom of page
  mov	ebx,[term_rows]
  dec	ebx
  dec	ebx		;remove header & menu lines
  dec	ebx
  shl	ebx,2		;index
  add	ebx,[index_ptr_curr_page]	; end of page +1
  cmp	eax,ebx
  jb	dk_exit1	;jmp if move ok
;we are at bottom of page
  add	[index_ptr_curr_page],dword 4
dk_exit1:
  mov	[index_ptr_selected],eax 
dk_exit2:
  mov	[main_loop_flag],byte display_body_state
  ret
;--------------------------------------------------------
delete:
  mov	esi,[index_ptr_selected]
  mov	esi,[esi]		;get pointer to clicked todo
  mov	al,[esi]		;get data from DEL column
  cmp	al,"D"			;delete already set?
  je	delete_unset		;jmp if delete already set
;set delete state
  mov	eax,'DEL '
  mov	[esi],eax
;force recycle field to lower case
  mov	eax,[esi+4]
  cmp	al,'9'			;eom here?
  jbe	not_eom
  or	eax,00202020h		;force lower case
  jmp	short recycle_unset2
not_eom:
  or	eax,00202000h
recycle_unset2:
  mov	[esi+4],eax
  jmp	short delete_exit
delete_unset:
  mov	eax,'_?_ '
  mov	[esi],eax
;leave recycle field unchanged
delete_exit:
  mov	[main_loop_flag],byte display_body_state
  ret
  
;--------------------------------------------------------
recycle:
  mov	esi,[index_ptr_selected]
  mov	esi,[esi]		;get pointer to clicked data
  mov	eax,[esi+4]		;get field contents
  cmp	ah,'Z'
  jbe	recycle_unset		;jmp if already set
;set recycle state
  cmp	[esi+4],byte '9'
  jbe	number_at_start		;jmp if number at start
  and	eax,0ffdfdfdfh		;assume fiele contains 'eom'
  jmp	short recycle_set	;
number_at_start:
  and	eax,0ffdfdfffh
recycle_set:
  mov	[esi+4],eax
;unset delete
  mov	eax,'_?_ '
  mov	[esi],eax
  jmp	short recycle_exit
recycle_unset:
  mov	eax,[esi+4]
  cmp	al,'9'			;eom here?
  jbe	no_eom
  or	eax,00202020h		;force lower case
  jmp	short recycle_set2
no_eom:
  or	eax,00202000h
recycle_set2:
  mov	[esi+4],eax
recycle_exit:
  mov	[main_loop_flag],byte display_body_state
  ret
		
;--------------------------------------------------------
link:
;extract link target, http or file
  mov	esi,[index_ptr_selected]
  mov	esi,[esi]	;get data ptr
;scan for bar or 0ah
link_scan_loop:
  lodsb
  cmp	al,'|'
  je	got_bar		;jmp if found
  cmp	al,0ah
  jne	link_scan_loop	;keep looking
  jmp	link_exit	;exit if no bar
got_bar:
  mov	edi,link_target
grab_target:
  lodsb
  stosb
  cmp	al,0ah
  jne	grab_target
  mov	[edi-1],byte 0	;;overwrite 0ah at end

;decode link field
  mov	esi,[index_ptr_selected]
  mov	esi,[esi]	;get ptr to data
  mov	al,[esi+20]	;get link field
  or	al,20h		;force lower case
  cmp	al,'e'		;edit?
  je	link_edit
  cmp	al,'v'		;view?
  je	link_view
  cmp	al,'o'		;open?
  je	link_open
  cmp	al,'f'		;file?
  je	link_file
  jmp	short link_exit	;ignore bad link field
link_edit:
  mov	esi,[m_edit_ptr]
  jmp	short link_build
link_view:
  mov	esi,[m_view_ptr]
  jmp	short link_build
link_open:
  mov	esi,[m_open_ptr]
  jmp	short link_build
link_file:
  mov	esi,[m_filer_ptr]
link_build:
  mov	edi,work_buf

link_mov_lp:
  lodsb
  cmp	al,' '
  jbe	lml_end
  stosb
  jmp	short link_mov_lp
lml_end:
  mov	al,' '
  stosb

 mov	esi,link_target
  call	str_move
  mov	esi,work_buf
  call	sys_shell_cmd
  jns	link_exit
  mov	esi,link_err_msg
  call	log_str
link_exit:
  mov	[main_loop_flag],byte display_all_state
  ret

;------------------
  [section .data]
link_target:	times 100 db 0
;link_edit_d:	db 'asmedit ',0
;link_view_d:	db 'asmview ',0
;link_open_d:	db 'xdg-open ',0
;link_file_d:	db 'asmfile ',0

link_err_msg:	db 0ah,'link access failed',0ah,0

  [section .text]  
;--------------------------------------------------------
abort:
  mov	[main_loop_flag],byte 5	;set abort state
  ret
;--------------------------------------------------------
normal_exit:
  mov	[main_loop_flag],byte exit_state
  ret
;--------------------------------------------------------
;add_todo:
;--------------------------------------------------------
;edit_todo: see edit.inc
;--------------------------------------------------------
;edit_all:   (see edit.inc)
;--------------------------------------------------------
;setup:      (see edit.inc)
;--------------------------------------------------------
;search:
;  ret
;--------------------------------------------------------

;--------------------------------------------------------
;--------------------------------------------------------
;--------------------------------------------------------
