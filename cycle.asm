
;   Copyright (C) 2007 Jeff Owens
;
;   This program is free software: you can redistribute it and/or modify
;   it under the terms of the GNU General Public License as published by
;   the Free Software Foundation, either version 3 of the License, or
;   (at your option) any later version.
;
;   This program is distributed in the hope that it will be useful,
;   but WITHOUT ANY WARRANTY; without even the implied warranty of
;   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;   GNU General Public License for more details.
;
;   You should have received a copy of the GNU General Public License
;   along with this program.  If not, see <http://www.gnu.org/licenses/>.

; main_loop_flag     0=winch
;                    1=display all
;                    2=display body
;                    3=try another input
;                    4=normal exit
;                    5=abort
winch_state	equ	0
display_all_state equ	1
display_body_state equ	2
ignore_state	equ	3
exit_state	equ	4
abort_state	equ	5

  [section .text]
;  extern signal_install_list
  extern key_decode2
  extern key_decode1
  extern process_search
  extern env_home2
  extern str_move
  extern strlen1
  extern file_open
  extern file_write
  extern env_exec
  extern enviro_ptrs
  extern dir_status
  extern dir_current
  extern dir_access
  extern terminal_type
  extern file_delete
  extern raw_set2,raw_unset2
  extern get_raw_time
  extern raw2ascii
  extern file_read_all
  extern blk_find
  extern read_one_byte
  extern crt_clear
  extern crt_str
  extern env_stack
  extern file_write_close
;  extern block_write_all
;  extern dword_to_l_ascii
;  extern crt_color_at
  extern move_cursor
  extern mov_color
;  extern file_delete
;  extern select_1up_list_left
;  extern crt_window
  extern mouse_enable
  extern mouse_line_decode
;  extern blk_find
  extern lib_buf
  extern delay

; ----------- Seasonal plan Program Version beta .1.0 ------------
;****
; NAME
;  cycle - todo and note taker
; INPUTS
;  * usage:  cycle <file>     
;  * A backup file may be stored at ~/.cycle
;  * -
;  * Program operations are optimized for mouse
;  * usage and a short help file is available
; OUTPUT
;  * Entries are stored in files
;  * if no file is provided a dummy file will be placed in /.cycle
; NOTES
; * file: cycle.sm
; * This file is a standalone ELF binary.
; * ----------------------------------------------
;*******
;%include "display.inc"
%include "wait_keysig.inc"
%include "edit.inc"
%include "actions.inc"
%include "find.inc"

[section .text]
;1 main *******************************************************************
; The program begins execution here...... 
;
  global  main

main:
  cld
  mov	[entry_stack_ptr],esp	;save for parameter decode
  call	env_stack		;get pointer to command line parameters
  call	find_paths		;find /.cycle, create if missing
  call	raw_set2	 	;keyboard to raw mode
  call	keysig_wait_set		;setup signal catching
  js	exit_only		;exit if error
  call	check_if_installed	;check if already running
  jc	exit_only		;exit if another cycle running
  call	check_if_in_terminal	;verify we have terminal
  jc	exit_only
  call	delete_old_log		;remove old log file
  call	parse_command_line	;set [target_file_ptr] if parameter found
  call	get_todays_date		;used by add_todo
  call	read_config		;get config file & set flags
  call	program_search		;check helpers set by read_config
  call	mouse_enable
re_read_todos:
  call	get_todo_file
  jc	exit_only
  call	index_todo_file
  call	sort_todos
  call	check_todo_file
  jc	exit_only		;jmp if error in todo file
winch_resize:
  call	debounce_winch		;debounce and setup window
main_loop:
  call	show_header
  cmp	[menu_mode],byte 0
  je	main_menu_display
  call	find_setup		;show find menu
  jmp	short main_loop2
main_menu_display:
  call	show_menu
main_loop2:
  call	display_todos
wait_for_input:
  call	keysig_wait		;wait for key,mouse,signal
  mov	al,[kbuf]
  cmp	al,-3		;timeout?
  je	main_loop	;loop if timeout
  cmp	al,-2			;signal?
  jne	check_mode
  call	decode_signal
  jmp	short main_tail
check_mode:
  cmp	[menu_mode],byte 1	;searh menu in control?
  je	find_menu
; decode input -> restart, main_loop, decode_key, mouse_event, exit
  cmp	al,-1
  je	mouse_hit
key_hit:
  call	decode_key
  jmp	short main_tail
;mouse hit comes here
mouse_hit:
  call	decode_mouse
  jmp	short main_tail
find_menu:
  mov	ecx,find_string
; ecx = process to execute if non-zero
main_tail:
  jecxz no_process
  call	ecx
; main_loop_flag set by process (see below)
no_process:
  mov	al,[main_loop_flag]
  cmp	al,winch_state
  je	winch_resize
  cmp	al,display_all_state
  je	main_loop
  cmp	al,display_body_state
  je	main_loop2
  cmp	al,ignore_state
  je	wait_for_input
  cmp	al,exit_state
  je	exit_request
;assume we are in abort state

; abort and log
  mov	esi,program_error
  call	log_str
  jmp	short exit_only

; exit path

exit_request:
  call	process_todos
  call	write_todos


exit_only:
  call	keysig_wait_close	;undo signal catching
  call	raw_unset2		;restore keyboard state
  mov	eax,[exit_screen_color]
  call	crt_clear
  xor ebx,ebx
  mov eax,1
  int 80h

;----------------
  [section .data]
; flag settings are: 0=winch
;                    1=display all
;                    2=display body
;                    3=try another input
;                    4=normal exit
;                    5=abort
main_loop_flag	db	display_all_state
;menu_mode settings are: 0=main menu
;                        1=find menu
menu_mode	db	0

program_error: db 'program aborted (signal)',0ah,0
  [section .text]
;-----------------------------------------------

check_if_installed:
  mov	byte [match_cnt],0
  call	process_scan
  cmp	byte [match_cnt],1
  je	cii_exit
;already_running log error here
  mov	esi,process_error
  call	log_str
  stc
cii_exit:
  ret
;--------------------------------------------------------------
; scan process table to see if multiple copies of "a" are
; executing.
;
process_scan:
  mov	eax,fbuf		;buffer for scan
  mov	ebx,max			;buffer length
  mov	ecx,our_name
ps_25:
  call	process_search
  or	eax,eax
  jz	ps_41			;jmp if end of process table
  js	ps_41			;jmp if error
; we have found a match
  inc	byte [match_cnt]
  xor	eax,eax			;set continue flag
  jmp	short ps_25
; adjust file names
ps_41:
  ret

  [section .data]
  
our_name:  db 'cycle',0
process_error: db 'existing process with name of cycle, aborting',0ah,0

match_cnt:  db 0
  [section .text]  
;---------------------------------------------------------------
;-----------------------------------------------------------------
; find ~/.cycle
;  inputs: [enviro_ptrs]
; output:
;          home_path = home path + /.cycle
;          edi = ptr to end of path
;
find_paths:
;
; look for home path
;
  mov	edi,home_path		;storage for "HOME" path
  call	env_home2
;append .cycle to home path
  mov	eax,edi
  add	eax,6
  mov	[path_ptr],eax

  mov	esi,path_append
  call	str_move
;check if ~/.cycle exists
  mov	ebx,home_path
  call	dir_status
  or	eax,eax
  jns	fp_exit			;exit if dir found
;create ~/.cycle
  mov	eax,39
  mov	ebx,home_path
  mov	ecx,40755q		;read/write flag
  int	80h			;create /home/xxxx/.cycle

fp_exit:
  ret

;---------------
 [section .data]

path_ptr	dd	0
path_append	db	'.cycle',0

 [section .text]
;---------------------------------------------------------
;  log_open - open file named "log" at ~/.cycle
; INPUTS
;  * none
; OUTPUT
;  * none (all registers restored)
;  [fd_open_flg] - global open fd for log
; NOTES
;  * source file: log.asm
;  * ----------------------------------------------

  global log_open
log_open:
  cld
  cmp	dword [fd_open_flg],0
  jne	lo_exit			;exit if log already open
  pusha

  mov	edi,[path_ptr]
  mov	esi,log_name
  call	str_move

  mov	ebx,home_path
  mov	ecx,1102q		;open read/write & create
  mov	edx,644q
  call	file_open
  mov	[fd_open_flg],eax
  popa
lo_exit:
  ret  
;-------
  [section .data]
log_name: db "/log",0
  global fd_open_flg
fd_open_flg:	dd	0		;file descriptor

  [section .text]
;---------------------------------------------------------
;****f* err/log_str *
; NAME
;>1 log-error
;  log_str - write string to file called "log"
; INPUTS
;    esi = string ptr for log file
; OUTPUT
;    none (all registers unchaged)
;    file "log" will have string appended to end
; NOTES
;    source file: log.asm
;<
;  * ----------------------------------------------
;*******
  global log_str
log_str:
  call	log_open
  pusha
  call	strlen1		;returns length in ecx
  mov	ebx,[fd_open_flg]
  mov	edx,ecx			;write x bytes
  mov	ecx,esi			;data to write
  call	file_write
  mov	byte [log_flag],1
  mov	byte [log_flag2],1
  popa
  ret
;---------------------------------------------------------
;****f* err/log_num *
; NAME
;>1 log-error
;  log_num - write number to file called "log"
; INPUTS
;    eax = binary number for log file
;          (convert to decimal ascii then written)
; OUTPUT
;    none (all registers unchanged)
;    file "log" will have <space>number<space> appended.
; NOTES
;    source file: log.asm
;<
;  * ----------------------------------------------
;*******
  extern dword_to_ascii
log_num:
  call	log_open
  pusha
  mov	edi,number
;  mov	esi,4			;store 4 digits
;  call	dword_to_l_ascii
  call	dword_to_ascii
  mov	al,' '
  stosb				;put space after number
  mov	byte  [edi],0		;put zero at end
  mov	ebx,[fd_open_flg]
  mov	ecx,number_start	;data to write
  mov	edx,edi			;edx= end of write
  sub	edx,ecx         	;compute write length
  call	file_write
  popa
  ret
;---------
  [section .data]
number_start: db ' '
number: times 10 db 0
  [section .text]
  
;---------------------------------------------------------------------
delete_old_log:
  mov	edi,[path_ptr]
  mov	esi,log_name
  call	str_move

  mov	ebx,home_path
  call	file_delete
  ret
;---------------------------------------------------------------------
view_log:
  mov	edi,[path_ptr]
  mov	esi,log_name
  call	str_move

  mov	edi,work_buf
  mov	esi,[m_view_ptr]
  cmp	[esi],byte 0
  jne	vl_move		;jmp if viewer found
  mov	esi,less_viewer
vl_move:
  call	str_move
  mov	al,' '
  stosb
  mov	esi,home_path
  call	str_move

  mov	esi,work_buf
  call	sys_shell_cmd
  mov	[main_loop_flag],byte display_all_state
  ret
;--------------
  [section .data]
less_viewer:	db 'more',0
  [section .text]
;---------------------------------------------------------------------
program_search:
  mov	esi,cfg_decode_ptrs
ttf_lp:
  push	esi
  mov	ebp,[esi]
  mov	ebx,[enviro_ptrs]
  xor	ecx,ecx
  call	env_exec		;search for executable
  jnc	ttf_skip		;jmp if file found
;program not found
  mov	esi,ttf_msg
  mov	edi,work_buf
  call	str_move

  pop	esi
  push	esi
  mov	esi,[esi]
  call	str_move
  mov	esi,work_buf
  call	log_str
;set this entry as null
  pop	esi
  push	esi
  mov	byte [esi],' '
ttf_skip:
  pop	esi
  add	esi,4
  cmp	dword [esi],0		;end of table?
  jnz	ttf_lp			;jmp if more data

ttf_exit:
  ret

  [section .data]
;------------------
ttf_msg: db 0ah,"install helper program shown or fix /.cycle/cycle.cfg - ",0

  [section .text]

;-----------------------------------------------------------
; sets carry if no terminal
;
check_if_in_terminal:
  call	terminal_type
  cmp	al,2
  jae	ciit_ok
  mov	esi,term_err_msg
  call	log_str
  stc
  jmp	short ciit_exit
ciit_ok:
  clc
ciit_exit:
  ret

;-------------
  [section .data]
term_err_msg: db "program not in terminal, aborting",0ah,0
  [section .text]
;-----------------------------------------------------------
; output:  eax negative = error
;          eax zero = [target_file] ptr built
;
parse_command_line:
  call	dir_current	;puts current working dir in lib_buf
  mov	ecx,7		;check for  read/write/execute
  call	dir_access
  or	eax,eax
  jp	pi_05		;jmp if current directory can be accessed
;error, can not access current dir
  mov	esi,err1
  jmp	short pi_exit1
pi_05:
;check if filename provided
  mov	esi,[entry_stack_ptr]
  lodsd			;get parameter count, 1=none
  dec	eax
  jz	pi_exit2	;jmp if no parameter entered
pi_10:
  lodsd			;eax=our executable name ptr
  lodsd			;eax=ptr to user parameter
  mov	[target_file_ptr],eax ;save filename ptr
  mov	byte [have_parameter],1
  xor	eax,eax
  jmp	short pi_exit2
pi_exit1:
  call	log_str
  xor	eax,eax
  dec	eax		;set eax = -1
pi_exit2:
  or	eax,eax
  ret
;--------------------
  [section .data]
entry_stack_ptr		dd 0
target_file_ptr:	dd 0
err1: db 0ah,0ah
  db 'can not access .cycle directory ',0ah,0
  [section .text]


;-----------------------------------------------------------
;    if signal kbuf has -2 at start, followed by pointer to return buffer
;       eax has size of return struc, may be multiple entries.
;       eax returned 0feh (254) in test. The buffer contained
;       dd 0fh <- signal number 15, SIGTERM
;       dd 0   (unused)
;       dd 0   sig code ?
;       dd 9ee <- PID of sender
;       dd 3e8 <- UID of sender
;   Signals handled and recomended action:
;    SIGWINCH                                - resize display
;    SIGCHLD,SIGTTIN,SIGTTOU,SIGINT,SIGQUIT  - log and ignore
;    SIGBUS,SIGFPE,SIGHUP,SIGILL,SIGPIPE     - log and abort
;    SIGSEGV,SIGTERM                         - log and abort

decode_signal:

;  mov	ebx,[kbuf+1]
;  xor	eax,eax
;  mov	al,[ebx]
;  call	log_num
;  mov	esi,signum_msg
;  call	log_str

;decode signal to set [main_loop_flag]
  mov	ebx,[kbuf+1]		;get ptr to struc
  mov	ah,[ebx]		;get signal number
  mov	esi,signal_decode_table
signal_decode_loop:
  lodsb
  or	al,al
  jz	sig_error
  cmp	al,ah			;found table match?
  je	sig_got
  lodsb				;move on
  jmp	short signal_decode_loop
sig_error:
  mov	[main_loop_flag],byte display_all_state
;;  jmp	ds_exit

sig_got:
  lodsb
  mov	[main_loop_flag],al

;  xor	eax,eax
;  mov	al,[main_loop_flag]	;;
;  call	log_num
;  mov	esi,signal_msg
;  call	log_str
ds_exit:
  xor	ecx,ecx		;no process
  ret

  [section .data]
;signal_msg: db " <main_loop_flag signal occured ",0ah,0
;signum_msg: db " <signal number",0ah,0

;winch_state	equ	0
;display_all_state equ	1
;display_body_state equ	2
;ignore_state	equ	3
;exit_state	equ	4
;abort_state	equ	5

signal_decode_table:
 db	28,0	;SIGWINCH,0	;do resize
 db	17,3	;SIGCHLD,3	;ignore
 db	21,3	;SIGTTIN,3
 db	22,3	;SIGTTOU,3
 db	2,3	;SIGINT,3
 db	3,4	;SIGQUIT,3
 db	8,5	;SIGFPE,4
 db	1,4	;SIGHUP,4	;click on terminal exit button
 db	4,5	;SIGILL,4
 db	13,5	;SIGPIPE,4
 db	11,5	;SIGSEGV,5
 db	15,4	;SIGTERM,4
 db	0		;end of table

  [section .text]
;-----------------------------------------------------------
; process mouse event
;   input:  kbuf has mouse data -1,button,col,row
; output: ecx = process to call
decode_mouse:
  mov	bl,[kbuf+2]	;get column 1+
  mov	bh,[kbuf+3]	;get row 1+
  mov	al,[kbuf+1]	;get event type
  mov	word [mouse_col],bx
  mov	byte [mouse_button],al
;compute menu row
  mov	cl,[term_rows]
  dec	cl
  cmp	bh,cl		;click on menu row?
  jae	menu_click	;jmp if menu click
  cmp	bh,1		;click on header?
  je	ignore_click	;jmp if click on header
;use row to find index entry
  xor	ecx,ecx
  mov	cl,bh		;ecx = row
  dec	ecx		;adjust for index lookup
  dec	ecx,		;adjust for index starting at 0
  shl	ecx,2		;ecx * 4
  add	ecx,[index_ptr_curr_page]
  cmp	[ecx],dword 0		;data here ?
  je	ignore_click
  mov	[index_ptr_selected],ecx
;check if click on field of interest, bl = click column
  mov	ecx,delete	;pre load delete process
  cmp	bl,3
  jbe	got_process	;jmp if delete
  mov	ecx,recycle
  cmp	bl,7
  jbe	got_process	;jmp if recycle
  cmp	bl,20
  jbe	ignore_click	;jmp if no process needed
  mov	ecx,link
  cmp	bl,23
  jbe	got_process	;jmp if link
ignore_click:
  mov	ecx,0		;no process	
got_process:		;ecx has process if any
;  xor	eax,eax
;  mov	al,[mouse_col]
;  dec	eax		;adjust for header
;  shl	eax,2		;compute index
;  add	eax,[index_ptr_curr_page]
;  cmp	[eax],dword 0
;  je	ignore_click	;jmp if no data here
;  mov	[index_ptr_selected],eax
  mov	[main_loop_flag],byte display_body_state
  jmp	mouse_exit

menu_click:
  mov	esi,menu_line1
  mov	edi,process_names
  mov	bl,[mouse_col]
  call	mouse_line_decode

mouse_exit:      
  ret
;---------------
 [section .data]

mouse_col	db	0	;data from vt100 mouse reporting
mouse_row	db	0	;data from vt100 mouse report
mouse_button	db	0	;data from vt100 mouse report (read_keys)

 [section .text]
;-----------------------------------------------------------
; decode_key - look up processing for this key
;  input - kbuf - has char zero terminated
;  output - ecx = ptr to processing or zero if no match
;           eax,ebx modified
decode_key:
  mov	esi,key_table1
  call	key_decode1
;  cmp	eax,alpha_key
;  jnz	dk_exit
;  mov	esi,key_table2
;  call	key_decode2
;  jnc	dk_exit
;  mov	eax,alpha_key
dk_exit:
  mov	ecx,eax
  ret

alpha_key:
  cmp	[kbuf],byte ' '		;space bar?
  jne	ak_10
  call	recycle
  mov	[main_loop_flag],byte display_body_state
  jmp	short ak_end
ak_10:	
  mov	[main_loop_flag],byte ignore_state
ak_end:
  ret

  [section .data]

key_table1:
  dd alpha_key			;alpha key presss  
  
  db 1bh,0		;esc
  dd escape_key

  db 1bh,5bh,36h,7eh,0		;21 key_pgdn
  dd page_down

  db 1bh,4fh,73h,0		;21 key_pgdn
  dd page_down
  
  db 1bh,5bh,35h,7eh,0		;16 key_pgup
  dd page_up
  
  db 1bh,4fh,79h,0		;16 key_pgup
  dd page_up

  db 1bh,5bh,41h,0		;15 key_up
  dd up_key

  db 1bh,4fh,41h,0		;15 key_up
  dd up_key

  db 1bh,4fh,78h,0		;15 key_up
  dd up_key

  db 1bh,5bh,42h,0		;20 key_down
  dd down_key

  db 1bh,4fh,42h,0		;20 key_down
  dd down_key

  db 1bh,4fh,72h,0		;20 key_down
  dd down_key

  db 1bh,5bh,33h,7eh,0		;23 key_del
  dd delete

  db 1bh,4fh,6eh,0		;23 key_del
  dd delete
 
  db 0
  dd alpha_key		;unknown key press

  [section .text]
;-----------------------
;---------------------------------------------------------------
read_config:
  mov	edi,[path_ptr]
  mov	esi,config_file_name
  call	str_move
;check if ~/.cycle/cycle.cfg exists
  mov	ebp,home_path	;ptr to file path
  mov	edx,size_config_buffer
  mov	ecx,config_buffer
  mov	al,1			;full path provided
  call	file_read_all		;open,read,close filel
;    eax = negative error (sign bit set for js,jns jump)
;          buffer too small returns error code -2
;    ebp = file permissions if eax positive
;    eax= lenght of read
;    ecx= buffer pointer if eax positive
;    edx= reported file size (save as read)
  jns	rc_50			;jmp if good read
  mov	byte [new_config],1
  mov	ebx,home_path
  mov	eax,config_buffer
  mov	ecx,size_config_buffer
  mov	esi,1			;flag
  call	file_write_close
  or	eax,eax
  jns	rc_50			;jmp if good write
; log
  mov	esi,config_write_error
  call	log_str
    
rc_50:
  call	build_config_data
  ret
;
  [section .data]
config_write_error db 0ah,"Error writing config file",0ah,0
  [section .text]
;-----------------
build_config_data:
  
  mov	esi,m_search
  mov	ebp,config_buffer_end	;end of search block
  mov	edi,config_buffer       	;top of search block
  mov	edx,1			;search forward
  mov	ch,0dfh			;ignoe case
  call	blk_find		;search for path=
  jc	config_error		;jmp if not found
  add	ebx,5			;move to start ofdata
  mov	[m_search_ptr],ebx
;if no entry, insert default
  cmp	[ebx],byte ' '		;blank field?
  jne	put_zero_at_end
  mov	edi,[path_ptr]
  mov	esi,cfg_append
  call	str_move
  mov	edi,ebx			;get config loc
  mov	esi,home_path		;default path
  call	str_move

put_zero_at_end:
  call	zero_terminate
;
; use table to process remaining strings in config
;
  mov	eax,cfg_decode_ptrs
  mov	[store_ptrs],eax
  mov	esi,cfg_decode_strings	;search string
  mov	[string_ptr],esi

bcd_loop:
  mov	esi,[string_ptr]
  cmp	[esi],byte 0
  je	bcd_exit		;exit if done
  mov	ebp,config_buffer_end	;end of search block
  mov	edi,config_buffer      	;top of search block
  mov	edx,1			;search forward
  mov	ch,0dfh			;ignore case
  call	blk_find		;search for save=
  jc	config_error		;jmp if not found
  add	ebx,5
  mov	eax,[store_ptrs]
  mov	[eax],ebx
  call	zero_terminate
;check if done
  mov	eax,[store_ptrs]
  add	eax,4			;move to next ptr
  mov	[store_ptrs],eax
  mov	esi,[string_ptr]
bcd_scan:
  lodsb
  cmp	al,0
  jne	bcd_scan
  mov	[string_ptr],esi
  jmp	short bcd_loop



config_error:
  mov	esi,config_msg
  call	log_str

;  mov	eax,[todo_data_color]
;  call	crt_clear
;  mov	ecx,config_msg
;  call	crt_str
;  mov	ecx,kbuf
;  call	read_one_byte  
bcd_exit:
  ret

; input ebx points to data terminated by space
zero_terminate:
  cmp	byte [ebx],' '
  jbe	zt_done		;jmp if space found
  inc	ebx
  jmp	short zero_terminate
zt_done:
  mov	[ebx],byte 0
  ret


  [section .data]
cfg_append:	db '/cycle.dat',0
config_msg: db 0ah
 db 'Error found in config file at /.cycle/cycle.cfg',0ah,0

config_file_name: db "/cycle.cfg",0
config_buffer:
 db '# config file for CYCLE program',0ah
 db '# Add data after equal signs, do not put space after =',0ah
 db 0ah  
 db '# leave blank for default of ~/.cycle/cycle.dat                    ',0ah
 db 'in-file-path=                                                  ',0ah
 db 0ah
 db '# backup of input file can be saved at ~/.cycle/cycle.bak',0ah
 db 'old_file_save=yes',0ah
 db 0ah
 db 'Editor=xdg-open',0ah
 db 'link-viewer=xdg-open',0ah
 db 'link-opener=xdg-open',0ah
 db 'link-filer=xdg-open',0ah
 times 200 db ' '
config_buffer_end:
size_config_buffer	equ	config_buffer_end - config_buffer

m_search: db 'path=',0
;s_search: db 'save=',0
m_search_ptr dd 0
;s_search_ptr dd 0

cfg_decode_strings:
  db	'save=',0
  db	'itor=',0	;editor
  db	'ewer=',0	;viewer
  db	'ener=',0	;opener
  db	'iler=',0	;filer
  db	0		;end of list

cfg_decode_ptrs:
m_save_ptr	dd	0
m_edit_ptr	dd	0
m_view_ptr	dd	0
m_open_ptr	dd	0
m_filer_ptr	dd	0
		dd	0	;end of pointers

store_ptrs	dd	0
string_ptr	dd	0 
;------------------------------------------------------
  [section .text]
get_todo_file:
  cmp	[have_parameter],byte 1
  jne	gtf_10		;jmp if no file given on command line
  mov	[have_parameter],byte 0	;clear flag so config filename takes over, needed for edit_all
  mov	ebx,[target_file_ptr]
  call	import
  jnc	gtf_exit	;jmp if good read
;no file on command line or parameter pointing to filename bad
gtf_10:
  mov	ebx,[m_search_ptr]
  mov	[target_file_ptr],ebx
  call	import
  jnc	gtf_exit	;jmp if good read
  cmp	[new_config],byte 1 ;first time program run
  jne	gtf_options
;this is first time program has been run, use default data file
  call	setup_default_todos
  jmp	short gtf_exit
;something is wrong, not first entry and no data file?
gtf_options:
  mov	esi,file_err_msg
  call	log_str
;  mov	eax,[todo_data_color]
;  call	crt_clear
;  mov	ecx,file_err_msg
;  call	crt_str
;  mov	ecx,kbuf
;  call	read_one_byte  
  stc			;set error flag
  jmp	short gtf_exit2

gtf_exit:
  xor	eax,eax		;set success flag
gtf_exit2:
  ret
;------------------------------------------------
;input: [target_file_ptr] points to file string
;output: carry set if error
import:
  mov	ebp,[target_file_ptr]	;ptr to file path
  mov	edx,max			;size of buffer
  mov	ecx,fbuf
  mov	al,1			;full path provided
  call	file_read_all		;open,read,close filel
;    eax = negative error (sign bit set for js,jns jump)
;          buffer too small returns error code -2
;    ebp = file permissions if eax positive
;    eax= lenght of read
;    ecx= buffer pointer if eax positive
;    edx= reported file size (save as read)
  jns	import_file_found
  stc	;set error flag
  jmp	short import_exit2
import_file_found:
  add	ecx,eax		;compute end of file
  mov	[file_end_ptr],ecx
  clc
import_exit2:
  ret
;------------------------------------------------
setup_default_todos:
  mov	esi,default_todo	;setup for str_move
  mov	edi,fbuf		;setup for str_move
  mov	[index_buf],edi		;create one entry in index
  mov	[index_buf +4],dword 0	;terminate index
  call	str_move
  mov	[file_end_ptr],edi

  mov	eax,index_buf
  mov	[index_ptr_curr_page],eax
  mov	[index_ptr_selected],eax
  ret

;------------------------------------------------  
;set carry if error
check_todo_file:
  mov	esi,fbuf	;pointer to todo's
  cmp	word [esi],'_?'
  jne	ctf_err		;jmp if error
  cmp	byte [esi+3],' '
  jne	ctf_err
  mov	eax,[esi+8]
  cmp	al,'2'
  jne	ctf_err
  clc
  jmp	short ctf_exit
ctf_err:
  mov	esi,bad_datafile_msg
  call	log_str

  stc
ctf_exit:
  ret
;--------------
  [section .data]
bad_datafile_msg: db 0ah,'Error in file cycle.dat',0ah,0
  [section .text]
;------------------------------------------------  
; get window size and set window parameters
debounce_winch:
  mov	eax,[term_rows]	;save current setting
  mov	[local_rows],eax
  mov	eax,[term_columns]
  mov	[local_columns],eax

;;  call	read_terminal_size
  mov	eax,100000000		;delay 
  call	delay
;;  call	read_terminal_size
  call	read_term_size
;check if window size has changed
  mov	eax,[term_rows]
  mov	ebx,[term_columns]
  cmp	eax,[local_rows]
  jne	debounce_winch
  cmp	ebx,[local_columns]
  jne	debounce_winch
;setup window parameters

;  mov	eax,[term_rows]
;  call	log_num
;  mov	esi,rowmsg
;  call	log_str
;  mov	eax,[term_columns]
;  call	log_num
;  mov	esi,colmsg
;  call	log_str

  ret

  [section .data]
rowmsg db ' rows',0ah,0
colmsg db ' cols',0ah,0
  [section .text]
;---------------------------------------------------
read_term_size:
  mov	ecx,5413h
  mov	edx,tbuf
  xor	ebx,ebx
  mov	eax,54
  int	byte 80h
  xor	eax,eax
  mov	ax,[edx]
  mov	[term_rows],ax
  mov	ax,[edx+2]
  mov	[term_columns],ax
  ret
;------------------------
 [section .data]
local_rows:	dd	0
local_columns:	dd	0
term_rows	dd	0
term_columns	dd	0
tbuf: times 10 db 0

  [section .text]

;------------------------------------------------  
; inputs: globals - term_rows,term_columns
;         
show_header:
  cmp	byte [log_flag],0
  je	sh_20		;jmp if no log
  mov	byte [log_show],2
sh_20:
  mov	esi,header_line1
  mov	ebp,header_color
  call	build_line
  mov	ax,0101h	;row 1 column1
  call	move_cursor
  mov	ecx,lib_buf	;buffer with display line
  call	crt_str		;display line
  ret
  [section .data]
header_line1:
  db 'DEL',1,'CYL',1,'   DATE   ',1,'LNK',1,' ACTION '
log_show: db 0,'  (check log) ',0
  [section .text]
;--------------------------------------------
;  input:  edi = end of status line
;
show_menu:
  mov	esi,menu_line1
  mov	ebp,menu_color_tbl
  call	build_line
  mov	ah,[term_rows]
  dec	ah
  mov	al,1
  call	move_cursor		;position cursor
  mov	ecx,lib_buf
  call	crt_str

  mov	esi,menu_line2
  mov	ebp,menu_color_tbl
  call	build_line
  mov	ah,[term_rows]
  mov	al,1
  call	move_cursor		;position cursor
  mov	ecx,lib_buf
  call	crt_str

  ret
;------------------------------------------
; build one display line using table
;  input: esi = table ptr
;         ebp = color table with 0 - spacer color (dword)
;                                1 - button 1 color
;                                2 - button 2 color
;
build_line:
  mov	edi,lib_buf
  mov	edx,[term_columns]
  mov	al,1
  call	set_menu_color
;
bl_10:
  lodsb
  cmp	al,8
  jb	bl_20    		;jmp if spacer between buttons
  call	stuff_char2		;store button text
  jne	short bl_10		;loop till end of screen
  jmp	bl_80			;jmp if end of screen
;
; we have encountered a spacer or end of table
;
bl_20:
  push	eax
  xor	eax,eax			;set color 0
  call	set_menu_color
  pop	eax
;
  cmp	al,0			;end of table
  je	bl_40			;jmp if end of table
;
; spacer char.
;
  mov	al,' '
  call	stuff_char2
  je	bl_80			;jmp if end of screen
  mov	al,[esi-1]		;get color code
  call	set_menu_color
  jmp	bl_10			;go up and move next button text
;
; we have reached the end of table, fill rest of line with blanks
;
bl_40:
  mov	al,' '
  call	stuff_char2
  jne	bl_40
;
; end of screen reached, terminate line
;
bl_80:
  mov	al,0
  stosb				;put zero at end of display
  ret  
;------------------------
;input: ebp=color table 
;       al = color code 0,1,2 to pick table entry

set_menu_color:
  xor	ebx,ebx
  mov	bl,al
  shl	ebx,2
  add	ebx,ebp		;look  up color
  mov	eax,[ebx]	;get color
  call	mov_color
  ret
;---------------------------
; input: [edi] = stuff point
;          al  = character
;         edx = screen size
; output: if (eq flag) end of line reached
;         if (non zero flag) 
;             either character stored
;                 or ecx decremented if not at zero
;
stuff_char2:
  cmp	edx,0
  je	stc_exit	;exit if at end of screen
  stosb			;move char to lib_buf
  dec	edx  
stc_exit:
  ret

;------------------------------------------------  
  [section .data]
;
; menu line codes: 1=spacer  0=end of data
;
menu_line1:
  db 1,' abort   ',1,' exit and ',1,' add   ',1,' edit     ',1,' edit ',1,' Setup ',1,' find '
log_flag	db 0,' view ',0
menu_line2:
  db 1,' no save ',1,' save data',1,' entry ',1,' selected ',1,' all  ',1,' config',1,'      '
log_flag2	db 0,' log  ',0
process_names:
  dd     abort,        normal_exit,   add_todo,   edit_todo,     edit_all,   setup,   find_setup, view_log,0

body_color_save	dd	0
;------------------------------------------------  
  [section .text]
;inputs: term_rows,term_columns
;        index_ptr_curr_page
;        index_ptr_selected
; 
display_todos:
  cld
  mov	[dt_row],dword 2		;starting row
; setup display row variable, index ptr variable, end of page index ptr
  mov	eax,[index_ptr_curr_page]
  mov	[dt_index_ptr],eax
;compute end of page
  mov	ebx,[term_rows]
  sub	ebx,3			
  shl	ebx,2
  add	ebx,eax			;compute end of page index
  mov	[dt_page_end_index],ebx
;display loop starts here
dt_loop:
  mov	[dt_columns],dword 0		;starting column
; setup lib_buf ptr
  mov	edi,lib_buf
  mov	esi,[dt_index_ptr]
; if current index is zero, stuff blanks
  cmp	[esi],dword 0
  jne	dt_got_data
;end of data, stuff blanks into screen line
  mov	dl,[term_columns]
  mov	edi,lib_buf
dt_20:
  mov	al,' '
  call	stuff_char
  jne	dt_20			;loop till line filled
  mov	byte [edi],0		;put zero at end of line
  jmp	dt_display

dt_got_data:
  cld
  mov	edi,lib_buf
; setup ptr to todo in fbuf
  mov	esi,[esi]	;get ptr to todo data	
;
  push	esi
  push	edi
  add	esi,8
  mov	edi,ascii_year
  mov	ecx,10
  repe	cmpsb
  pop	edi
  pop	esi

  mov	eax,[todo_due_color]
  jbe	set_color
  mov	eax,[todo_data_color]
set_color:
  mov	[body_color_save],eax
  call	mov_color
  
; check DEL/? and set color

  cmp	[esi],byte '_'
  je	dt_keep_color1
  mov	eax,[recycle_on_color]
  call	mov_color
dt_keep_color1:
; copy DEL/?
  mov	ecx,3
  call	mov_data		;move "DEL" or "_?_"

  mov	eax,[body_color_save]
  call	mov_color		;space color
  mov	al,' '
  call	stuff_char			;move space
  inc	esi

; check if recycle set, and select color
  test	[esi+1],byte 20h
  jnz	dt_keep_color2
  mov	eax,[recycle_on_color]
  call	mov_color
; copy recycle state
dt_keep_color2:
  mov	ecx,3
  call	mov_data		;move recycle state

  mov	eax,[body_color_save]
  call	mov_color
  mov	al,' '
  call	stuff_char		;move space
  inc	esi

; copy date

  mov	ecx,10
  call	mov_data		;move date

;insert * if link found

  mov	eax,[body_color_save]
  call	mov_color
  mov	al,' '
  call	stuff_char		;move space

;set link color


  mov	al,"_"
  call	stuff_char		;move first byte of link field

  add	esi,2			;move to link field
  cmp	[esi],byte '_'		;link here?
  je	no_link
  mov	al,"*"			;found link
no_link:
  call	stuff_char		;store "*" or " "
  mov	al,'_'
  call	stuff_char		;final space in link field

  add	esi,5			;move to end of input link field

;set space color
  mov	eax,[body_color_save]
  call	mov_color

  mov	al,' '
  call	stuff_char		;move space

; is this todo selected, if so use selected color
  mov	ecx,[dt_index_ptr]
  cmp	ecx,[index_ptr_selected]
  jne	not_selected		;jmp if not selected
 
  mov	eax,[selected_color]
  call	mov_color
not_selected:  
; copy body of todo
body_copy_loop:
  lodsb
  cmp	al,'|'
  je	bcl_done
  cmp	al,0ah
  je	bcl_done
  call	stuff_char
  jmp	short body_copy_loop
bcl_done:

;fill remainder of line with blanks
dt_90:
  mov	al,' '
  call	stuff_char
  jne	dt_90			;loop till line filled

; display todo
dt_display:
  mov	al,0
  stosb				;terminate todo line
  mov	al,1			;colulmn 1
  mov	ah,[dt_row]		;row x 
  call	move_cursor 
  mov	ecx,lib_buf
  call	crt_str
; bump row and index ptr.
  inc	dword [dt_row]

; check if done with page, if no -> display loop
  mov	esi,[dt_index_ptr]
  add	esi,4
  mov	[dt_index_ptr],esi
  cmp	esi,[dt_page_end_index] ;done?
  jae	dt_done
  jmp	dt_loop
dt_done:
  ret
;---------------------------------------------------
;input esi = from ptr
;      edi = to ptr
;      ecx = count
;      [dt_columns] = current column posn
;output: dt_columns updated
;        esi,edi moved
;        ecx counted down if not at end of screen
;        eq flag set if at end of screen      
mov_data:
  mov	ebx,[dt_columns]
md_loop:
  cmp	ebx,[term_columns]
  je	md_exit		;exit if at end if screen
  movsb
  inc	ebx
  loop	md_loop
  mov	[dt_columns],ebx
  stc
md_exit:
  ret

;---------------------------------------------------
; input: esi = data ptr, (not used)
;        al = char to store
;        edi = storage point
;        [dt_columns] = current column
;        [term_columns] = max column
; output: edi moved if not at end of screen
;         [dt_columns] bumped if not at end of screen
;         eq flag set if at end of screen;
stuff_char:
  mov	ebx,[dt_columns]
  cmp	ebx,[term_columns]
  jae	sc_exit		;exit if at end of page
  stosb		;store char
  inc	ebx
  mov	[dt_columns],ebx
sc_exit:
  ret
;---------------
  [section .data]
dt_row	dd	0	;display row counter
dt_columns dd	0	;build column count
dt_index_ptr dd	0	;index display point
dt_page_end_index dd 0	;beyond last display index
  [section .text]
;------------------------------------------------------
get_todays_date:
  call	get_raw_time	;raw weconds in eax
  mov	edi,ascii_year	;destination for data
  mov	ebx,format
  call	raw2ascii

  mov	eax,[ebx+time.yr]
  mov	[year],eax

  mov	eax,[ebx+time.dy]
  mov	[day_of_month],eax

  mov	eax,[ebx+time.mo]
  mov	[month_number],eax

  ret
;-------------------------
  [section .data]
format: db "0/1/2",0
ascii_year:	db	"yyyy"
                db      "/"
ascii_month:	db	"mm"
                db	"/"
ascii_day	db	"dd"
		db	0	;end of string for str_move

year		dd	0
day_of_month	dd	0
month_number	dd	0

  [section .text]
;-------------------------------------------------
  [section .data]
new_config:	db 0	;1=config file not found, using default
have_parameter  db 0	;1=file parameter entered [target_file_ptr] set

default_todo: db "_?_ ___ 08/31/1942A VIEW sample entry pointing to help|help.txt",0ah
default_todo_end  db  0	;do not move, end of default_todo0
file_err_msg db 0ah,'can not read data file. Press any key to exit',0ah,0
  [section .text]
;
;----------------------------------------------------------------------
  [section .data]
;------------------------------------------------------------------------

; colors = aaxxffbb  (aa-attribute ff-foreground  bb-background)
;   30-black 31-red 32-green 33-brown 34-blue 35-purple 36-cyan 37-grey
;   attributes 30-normal 31-bold 34-underscore 37-inverse
;
;header colors
header_color	dd	31003730h
header_button	dd	31003036h

;todo body colors
selected_color		dd 	30003037h
button_color		dd 	30003037h
;todo_data_color	dd 	31003734h	;normal pending todo
todo_data_color		dd 	30003734h	;normal pending todo
;todo_due_color		dd	30003436h	;due color
todo_due_color		dd	31003734h	;due color
recycle_on_color	dd	30003037h	;selected fields in body

exit_screen_color	dd 	31003037h
;----------------------------------------------------------  
menu_color_tbl:
	dd	31003734h	;spacer color
	dd	30003037h	;button 1 color
	dd	31003134h	;button 2 color

find_color_tbl:
string_menu_color	dd	31003734h	;spacer color
string_button_color1	dd	30003037h	;button 1 color
string_button_color2	dd	31003134h	;button 2 color

entry_string_color	dd	30003436h
entry_cursor_blink	dd	35003436h

;--- unitialized data -------------------------------------

  [section .bss]
  [bits 32]



home_path	resb	140

;

; file buffer for todo's
;
max equ 200000
fbuf	resb	max
fbuf_end resb	1
file_end_ptr	resd	1	;next available loc for todo
;
; index buf 
index_buf resb	max/20		;last entry has zero
index_buf_end resb 1
index_ptr_curr_page	resd	1
index_ptr_selected	resd	1
;
work_buf_size	equ	2000
work_buf	resb	work_buf_size

