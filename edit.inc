  [section .text]
  extern sort_selection
  extern sys_run_wait

  [section .text]
;------------------------------------------------
; edit cycle.cfg
;
setup:

  mov	edi,[path_ptr]
  mov	esi,config_file_name
  call	str_move

  mov	edi,work_buf
  mov	esi,[m_edit_ptr]
  call	str_move
  mov	al,' '
  stosb
  mov	esi,home_path
  call	str_move

  mov	esi,work_buf
  call	sys_shell_cmd
  js	setup_error	;jmp if error
  call	read_config
  call	program_search
  jmp	short setup_exit
setup_error:
  mov	esi,setup_msg
  call	log_str
setup_exit:
  mov	[main_loop_flag],byte display_all_state	;redisplay header incase of error
  ret
;
  [section .data]
setup_msg:	db 0ah,'failure to edit config file',0ah,0
  [section .text]
;------------------------------------------------
;input: [index_ptr_selected] = line to cut
;       index_buf terminated by zero
;
; output: lib_buf contains cut line
;         holes in fbuf and index closed
cut_line:
  mov	esi,[index_ptr_selected]
  mov	esi,[esi]
  push	esi		;save starting point
  mov	edi,lib_buf
cl_move_lp:
  lodsb
  stosb
  cmp	al,0ah
  jne	cl_move_lp	;loop till line moved
  mov	[edi],byte 0	;put zero at end
; esi points to end of line
; setup to close hole in fbuf
  pop	edi		;get "to" ptr
cl_close_lp:
  cmp	esi,[file_end_ptr]
  jae	cl_done
  lodsb
  stosb
  jmp	short	cl_close_lp
cl_done:
  mov	[file_end_ptr],edi ;set new file end
  mov	[edi],byte 0	;put zero just for visual check
;fix index, must reindex because things have moved
  call	index_todo_file
  ret
  
;------------------------------------------------
;remove todo from fbuf, ignore index
;input: esi=ptr to todo
;
cut_todo:
  push	esi		;save starting point
ct_scan_lp:
  lodsb
  cmp	al,0ah
  jne	ct_scan_lp	;loop till line moved
;  mov	[edi],byte 0	;put zero at end
; esi points to end of line
; setup to close hole in fbuf
  pop	edi		;get "to" ptr
ct_close_lp:
  cmp	esi,[file_end_ptr]
  je	ct_close_done
  lodsb
  stosb
  jmp	short ct_close_lp
ct_close_done:
  mov	[file_end_ptr],edi ;set new file end
  mov	[edi],byte 0	;put zero just for visual check
  ret
;------------------------------------------------

edit_todo:
  call	cut_line
  call	edit_engine
  ret
;----------------------------------------------------
; input: line at top of lib_buf, terminated with 0ah,0

edit_engine:
 
;move form to work buff
  mov	esi,todo_entry_form
  mov	edi,work_buf
  call	str_move

edit_line:
  cld
;fill form fields
  mov	esi,lib_buf		;get pointer to "_?_"
  mov	edi,del_stuff - todo_entry_form + work_buf
  mov	ecx,3
  rep	movsb			;move _?_
;
  mov	esi,lib_buf+4
  mov	edi,recycle_stuff - todo_entry_form + work_buf
  mov	ecx,3
  rep	movsb

;  mov	esi,ascii_year
  mov	esi,lib_buf+8
  mov	edi,date_stuff - todo_entry_form + work_buf
  mov	ecx,10
  rep	movsb

  mov	al,[lib_buf+18]	;get priority
  mov	[priority_stuff - todo_entry_form + work_buf],al

  mov	esi,lib_buf+25
  mov	edi,body_stuff - todo_entry_form + work_buf
body_cpy_loop:
  lodsb
  cmp	al,'|'
  je	ccl_done
  cmp	al,0ah
  je	ccl_done
  stosb
  jmp	short body_cpy_loop
ccl_done:

  cmp	al,"|"
  jne	no_link_copy
;copy link data
  mov	edi,ldata_stuff - todo_entry_form + work_buf
ls_loop:
  lodsb
  stosb
  cmp	al,0ah
  jne	ls_loop
  mov	eax,[lib_buf+20]
  mov	[link_stuff-todo_entry_form+work_buf],eax
no_link_copy:

;write form to file at /.cycle/form
  mov	edi,[path_ptr]
  mov	esi,form_filename
  call	str_move	;buil name at /home_path
;
  mov	ebx,home_path
  mov	ecx,work_buf
  mov	esi,form_end - todo_entry_form ;compute file lenght
  xor	edx,edx			;default permissions
  call	block_write_all
;  js	wsp_error

;launch editor on file
  mov	edi,work_buf
  mov	esi,[m_edit_ptr]
  call	str_move
  mov	al,' '
  stosb
  mov	esi,home_path
  call	str_move

  mov	esi,work_buf
  call	sys_shell_cmd

;read file to lib_buf
  mov	ebp,home_path	;ptr to file path
  mov	edx,work_buf_size	;size
  mov	ecx,work_buf      
  mov	al,1			;full path provided
  call	file_read_all		;open,read,close filel
;    eax = negative error (sign bit set for js,jns jump)
;          buffer too small returns error code -2
;    ebp = file permissions if eax positive
;    eax= lenght of read
;    ecx= buffer pointer if eax positive
;    edx= reported file size (save as read)
  jns	et_50			;jmp if good read

  mov	esi,edit_file_err_msg
  call	log_str
  jmp	etl_exit

;build entry in lib_buf, from data in work_buf
et_50:

  mov	edi,work_buf
  mov	esi,del_equal
  call	str_search
  jc	et_fail
  mov	[del_equal_ptr],edi

  mov	esi,recycle_equal
  call	str_search
  jc	et_fail
  mov	[recycle_equal_ptr],edi		;save ptr to recycle data

  mov	esi,date_equal
  call	str_search
  jc	et_fail
  mov	[date_equal_ptr],edi

  mov	esi,priority_equal
  call	str_search
  jc	et_fail
  mov	[priority_equal_ptr],edi

  mov	esi,todo_equal
  call	str_search
  jc	et_fail
  mov	[todo_equal_ptr],edi

  mov	esi,link_equal
  call	str_search
  jc	et_fail
  mov	[link_equal_ptr],edi

  mov	esi,ldata_equal
  call	str_search
  jc	et_fail
  mov	[ldata_equal_ptr],edi
  jmp	short build_entry
et_fail:
  mov	esi,edit_todo_format_err
  call	log_str
  jmp	etl_exit2

;build todo in lib_buf format = DEL CYL yyyy/mm/ddP LINK ..... |      0ah
build_entry:
  mov	edi,lib_buf
  mov	esi,[del_equal_ptr]
  mov	ecx,3
  rep	movsb
  mov	al,' '
  stosb

  mov	esi,[recycle_equal_ptr]
  mov	ecx,3
  rep	movsb
  mov	al,' '
  stosb

  mov	esi,[date_equal_ptr]
  mov	ecx,10
  rep	movsb

  mov	esi,[priority_equal_ptr]
  movsb
  mov	al,' '
  stosb

  mov	esi,[link_equal_ptr]
  mov	eax,[esi]
  stosd			;store link
  mov	al,' '
  stosb

  mov	esi,[todo_equal_ptr]
etlpa:
  lodsb			;scan to end of entry
  cmp	al,'|'
  je	etlpa_end
  cmp	al,0ah
  jbe	etlpa_end
  jmp	short etlpa
etlpa_end:
  dec	esi		;move back to 0ah
etlpa_lp2:
  dec	esi		;strip spaces from end
  cmp	[esi],byte ' '
  je	etlpa_lp2
  mov	[esi+1],byte 0	;terminate entry

  mov	esi,[todo_equal_ptr]
etlp1:
  lodsb
  cmp	al,0ah
  jbe	etlp1_end
  stosb
  jmp	short etlp1
etlp1_end:

  mov	esi,[ldata_equal_ptr]
  cmp	[esi],byte " "
  jbe	etlp2_end

  mov	esi,[ldata_equal_ptr]
etlpb:
  lodsb			;scan to end of entry
  cmp	al,0ah
  je	etlpb_end
  jmp	short etlpb
etlpb_end:
  dec	esi		;move back to 0ah
etlpb_lp:
  dec	esi		;strip spaces from end
  cmp	[esi],byte ' '
  je	etlpb_lp
  mov	[esi+1],byte 0	;terminate entry

  mov	esi,[ldata_equal_ptr]
  mov	al,'|'
  stosb
etlp2:
  lodsb
  cmp	al,0ah
  jbe	etlp2_end
  stosb
  jmp	short etlp2
etlp2_end:
  mov	al,0ah
  stosb

;add todo, edi points to end of todo in lib_buf
  mov	esi,lib_buf
  call	add_line
etl_exit2: 
;re-index
  call	index_todo_file
;sort todos
etl_exit:
  call	sort_todos
  mov	[main_loop_flag],byte display_all_state
  ret

;--------------
  [section .data]

edit_file_err_msg db 0ah,'Error reading edit file',0ah,0
edit_todo_format_err db 0ah,'Error in edit entry format',0ah,0

del_equal	db	'DEL=',0
del_equal_ptr	dd	0
recycle_equal	db	'CLE=',0
recycle_equal_ptr dd	0
date_equal	db	'ATE=',0
date_equal_ptr	dd	0
priority_equal	db	'ITY=',0
priority_equal_ptr dd	0
todo_equal	db	'ODO=',0
todo_equal_ptr	dd	0
link_equal	db	'INK=',0
link_equal_ptr	dd	0
ldata_equal	db	'ATA=',0
ldata_equal_ptr	dd	0

form_filename	db	"/form.dat",0

todo_entry_form:
 db 'enter todo data at bottom using instructions that follow:',0ah
 db 0ah
 db 'DEL - enter  DEL  to delete or _?_ for normal state',0ah
 db 'RECYCLE - enter           1yr,2yr,..9yr = annual recycling',0ah
 db '                           1mo,2mo,..9mo = monthly recycling',0ah
 db '                           1wk,2wk,..9wk = weekly recycleing',0ah
 db '                           1da,2da,..9da = daily recycling',0ah
 db '                           0da or blank for no recycling',0ah
 db '                           eom for end of month recycling',0ah
 db 'DATE - enter as yyyy/mm/dd',0ah
 db 'PRIORIRY - daily priority, and char can be used',0ah
 db 'TODO - enter text for todo',0ah
 db 'LINK - process LDATA field by',0ah
 db '                set link as: (blank) = no linked data',0ah
 db '               VIEW = open link field as text view (asmview)',0ah
 db '               EDIT = open link field with editor (asmedit)',0ah
 db '               OPEN = open link field with xdg-open',0ah
 db '               FILE = open link field as directory',0ah
 db ' LDATA - optional link field, single name = note stored at /.cycle/note',0ah
 db '                     full path can be any local file',0ah
 db '                     html:// can be used with OPEN',0ah
 db '------------------------------------------------------------------------',0ah
 db 0ah
 db 'DEL=_?_',0ah
del_stuff	equ	$-4
 db 'RECYCLE=   ',0ah
recycle_stuff	equ	$-4
 db 'DATE=2013/09/11',0ah
date_stuff	EQU	$-11
 db 'PRIORITY=P',0ah
priority_stuff	equ	$-2
 db 'TODO='
body_stuff	equ	$
 times 200 db " "
 db 0ah
 db 'LINK=____',0ah
link_stuff	equ	$-5
 db 'LDATA='                                                                                                                                                                                                        
ldata_stuff	equ	$
 times 200 db " "
 db 0ah
form_end:
 db 0
;------------
template_todo: db '_?_ '
               db '1yr '
template_date: db 'yyyy/mm/dd'
		db 'P ____ ?   ',0ah,0
  [section .text]
;------------------------------------------------
add_todo:
  mov	esi,ascii_year
  mov	edi,template_date
  call	str_move
  mov	[edi],byte "P"
  mov	esi,template_todo
  mov	edi,lib_buf
  call	str_move
  call	edit_engine	;lib_buf contains template
  ret
;------------------------------------------------
; input: file_end_ptr - end of entries
;        esi = ptr to string, added to end of database
;     note: must reindex after adding
;
add_line:
  cld
  mov	edi,[file_end_ptr]
al_loop:
  lodsb
  stosb
  cmp	al,0ah
  jne	al_loop
  mov	[file_end_ptr],edi
  ret
;------------------------------------------------
;
sort_todos:
  mov	esi,fbuf		;sort buffer
  mov	ebp,index_buf		;index buffer
  mov	edx,9			;sort from column 0
  mov	ecx,11			;length of sort
  call	sort_selection
  ret

;------------------------------------------------
; input: fbuf,[file_end_ptr]
; output: index_buf, index_buf pointers  
index_todo_file:
  mov	esi,fbuf		;start of todo's
  mov	edi,index_buf		;start of indexes
cai_loop1:
  cmp	esi,[file_end_ptr]
  jae	cai_done		;jmp if done
  mov	[edi],esi		;insert index
  add	edi,4			;move to next index stuff
;search for next todo
cai_loop2:
  lodsb				;get next todo char
  cmp	al,0ah
  je	cai_loop1 		;jmp if end of todo
  cmp	esi,[file_end_ptr]
  jb	cai_loop2		;jmp if more data
cai_done:
  mov	[edi],dword 0		;terminate index's
  add	edi,4
  cmp	edi,index_buf_end	;end of index?
  jb	cai_done		;keep clearing index
  mov	eax,index_buf
  mov	[index_ptr_curr_page],eax
  mov	[index_ptr_selected],eax
  ret
;----------------------------------------------------------
  extern block_open_write,block_close
;
;input: index_buf - contains sorted todo pointers
;       home_path - pointer to home
;       path_ptr - points at end of /home/jeff/.cycle
;       m_search_ptr - pointer to input file if not parameter, if
;                      m_search_ptr -> space or 0ah then use default
;       (assume todo's are sorted)
;
write_sorted_todos:
  call	backup		;make backup as needed
  mov	esi,[m_search_ptr]
  mov	al,[esi]	;get first char from config file entry
  cmp	al,' '
  ja	wst_20		;jmp if name found
;no congig name, use default
  mov	edi,[path_ptr]
  mov	esi,default_sorted_file
  call	str_move	;buil name at /home_path
  mov	esi,home_path
wst_20:
  mov	edi,sorted_filename
  call	str_move
;file name now at sorted_filename
  mov	ebx,sorted_filename
;;  mov ecx,O_WRONLY_CREAT_TRUNC
  xor	edx,edx			;default permissions
  call	block_open_write
  js wsp_error
;
; use index to find next todo
;
  mov	ebp,index_buf
wsp_lp1:
  mov	esi,[ebp]		;get todo ptr
  mov	ecx,esi			;save todo ptr
  or	esi,esi
  jz	wsp_done		;jmp if all todo's written
  sub	edx,edx
wsp_lp2:
  cmp	byte [esi],0ah
  je	wsp_10			;jmp if end of todo found
  inc	esi			;move ptr
  inc	edx  			;bump count
  jmp	wsp_lp2
wsp_10:
  inc	edx
;
; write to file
;  ebx = file descriptor
;  ecx = data pointer
;  edx = lenght of write
;
  mov	eax,4
  int	80h			;file write
  js	wsp_error
  add	ebp,4			;move to next record
  jmp	wsp_lp1
;
; error processing
;
wsp_error:
  mov	esi,wsp_err
  call	log_str
  jmp	wsp_done2  
;
; all data has been written, close file
;
wsp_done:
  call	block_close
  js	wsp_error
wsp_done2:
  ret
;-----------------------------------------------------------
  extern block_write_all

write_todos:
  call	backup		;make backup as needed
  mov	esi,[m_search_ptr]
  mov	al,[esi]	;get first char from config file entry
  cmp	al,' '
  ja	wt_20		;jmp if name found
;no congig name, use default
  mov	edi,[path_ptr]
  mov	esi,default_sorted_file
  call	str_move	;buil name at /home_path
  mov	esi,home_path
wt_20:
  mov	edi,sorted_filename
  call	str_move
;file name now at sorted_filename
  mov	ebx,sorted_filename
  mov	esi,[file_end_ptr]
  mov	ecx,fbuf
  sub	esi,ecx			;compute file lenght
  xor	edx,edx			;default permissions
  call	block_write_all
  js	wsp_error
  ret

;-----------------
  [section .data]

wsp_err: db 0ah,'write_file error',0ah,0

;shell_cmd: db 'leafpad '		;the file name must follow this
sorted_filename: times 100 db 0

default_sorted_file: db '/cycle.dat',0
ea_err_msg: db 0ah,'failed to edit cycle database',0ah,0

backup_done_flag	db	0	;0=not done
backup_filename		db	'/cycle.bak',0

  [section .text]
;-----------------------------------------------------------------------------
  extern file_copy

backup:
  mov	esi,[m_save_ptr]
  mov	al,[esi]		;get backup flag
  or	al,20h
  cmp	al,'y'			;yes backup?
  jne	backup_exit
  cmp	[backup_done_flag],byte 0
  jne	backup_exit		;exit if already backed up
;backup input file
  mov	esi,[m_search_ptr]
  mov	al,[esi]	;get first char from config file entry
  cmp	al,' '
  ja	bk_20		;jmp if name found
;no congig name, use default
  mov	edi,[path_ptr]
  mov	esi,default_sorted_file
  call	str_move	;buil name at /home_path
  mov	esi,home_path
bk_20:
  mov	edi,sorted_filename
  call	str_move
;file name now at sorted_filename
  mov	edi,[path_ptr]
  mov	esi,backup_filename
  call	str_move
;destination file now at home_path
;setup for copy
  mov	cl,9h	;flags
  mov	ebx,sorted_filename	;from name
  mov	edx,home_path		;to name
  call	file_copy
  mov	[backup_done_flag],byte 1	;set backup done
backup_exit:
  ret  

;-----------------------------------------------------------------------------
  extern sys_shell_cmd

edit_all:
  call	sort_todos
  call	write_sorted_todos
;launch leafpad

  mov	edi,work_buf
  mov	esi,[m_edit_ptr]
  call	str_move
  mov	al,' '
  stosb
  mov	esi,sorted_filename
  call	str_move

  mov	esi,work_buf
  call	sys_shell_cmd
  js	ea_error
  call	get_todo_file
  call	index_todo_file
  call	sort_todos
  call	check_todo_file
  jmp	short ea_exit
ea_error:
  mov	esi,ea_err_msg
  call	log_str
ea_exit:
  mov	[main_loop_flag],byte display_all_state
  ret
 
;-------------------------------------------------------------------



process_todos:
  mov	esi,fbuf		;ptr to first todo
pt_loop:
  cmp	esi,[file_end_ptr]
  jae	pt_exit			;exit if done
  mov	al,[esi]		;get delete field char
  cmp	al,'D'
  je	pt_10			;jmp if delete set
  mov	al,[esi+4]		;get recycle field
  cmp	al,'0'
  jne	pt_20			;jmp if not recycle delete
  mov	al,[esi+5]
  test	al,20h			;upper case?
  jnz	pt_20			;jmp if lower case
;cut todo
pt_10:
  push	esi
  mov	[index_ptr_selected],esi
  call	cut_todo
  pop	esi
  jmp	short pt_loop
;check recycle field
pt_20:
  mov	al,[esi+5]	;get second char of recycle field
  test	al,20h		;check case
  jnz	pt_tail		;jmp if upper (no recycle)
;reschedule the todo
  call	reschedule_todo
;scan to next todo
pt_tail:
  lodsb
  cmp	al,0ah
  jne	pt_tail
  jmp	pt_loop
pt_exit:
  ret
;---------------------------------------------------------------
  extern days_in_month
;-----------------------------------------------------------
  [section .text]

;-------------------------------------------------------------------
; inputs:  esi = pointer to current todo
;          resched_table (see edit.inc)
; output:  esi = unchanged
;
reschedule_todo:
  push	esi
  mov	esi,ascii_year
  call	ascii2days
  mov	[today_days],eax

  pop	esi			;get todo ptr
  push	esi			;save it
  mov	ax,[esi + 5]			;get reschedule code
  or	ax,2020h			;convert to lower case
  mov	[esi +5],ax			;update data
;decode recycle code
  cmp	ax,'da'
  je	day_reschedule
  cmp	ax,'wk'
  je	week_reschedule
  cmp	ax,'mo'
  je	month_reschedule
  cmp	ax,'yr'
  je	year_reschedule
  cmp	ax,'om'
  je	eom_reschedule
  jmp	r_exit2		;jmp if error in data

day_reschedule:
  add	esi,year_field
  push	esi
  call	ascii2days		;sets eax=days since 1970
  pop	edi			;storage point
  xor	ebx,ebx
  mov	bl,[edi-4]		;get number
  and	bl,0fh
  add	eax,ebx
  call	bin_to_date
  jmp	r_exit

week_reschedule:
  add	esi,year_field
  push	esi
  call	ascii2days		;sets eax=days since 1970
  pop	edi			;storage point
  mov	bl,[edi-4]		;get number of weeks
  and	bl,0fh			;convert to bin
another_week:
  add	eax,7
  dec	bl
  jnz	another_week
  call	bin_to_date
  jmp	r_exit

month_reschedule:
  add	esi,year_field
  mov	bl,[esi-4]		;get mount count
  and	bl,0fh			;make binary
  call	bump_months
  jmp	r_exit

year_reschedule:
  add	esi,year_field
  xor	ecx,ecx
  mov	cl,[esi-4]		;get year count
  and	cl,0fh			;convert to bin
  jecxz	r_exit
  xor	ebx,ebx
another_year:
  add	ebx,12
  loop	another_year
  call	bump_months
  jmp	r_exit

eom_reschedule:
  or	[esi+4],byte 20h
  add	esi,year_field
  push	esi
  call	ascii2regs			;sets [year,month_number,day_of_month]
  inc	ah
  cmp	ah,12
  jbe	re_ok				;jmp if month ok
  mov	ah,1
  inc	edx				;move to next year
re_ok:
  push	eax
  mov	bl,ah				;get month
  call	days_in_month
  pop	eax
  mov	al,bl				;set days
  pop	edi				;get storage point
  call	regs_to_date

r_exit:
  pop	esi		;restore entry ptr
  push	esi		;save it
  add	esi,year_field
  call	ascii2days		;sets eax=days since 1970
  cmp	eax,[today_days]	;are we less than today
  ja	r_exit2			;jmp if ok
  pop	esi
  jmp	reschedule_todo		;loop back

r_exit2:
  pop	esi
  ret

  [section .data]
today_days:	dd 0 ;todays date in total days since 1970
  [section .text]
	
year_field	equ	8  
;-------------------------------------------------------------------
; inputs:  bl = number of months to bump
;          esi = ptr to todo
;          [year,month_number,day_of_month]
;
bump_months:
;  add	esi,year_field			;point at date
  push	esi				;save ascii date ptr
  push	ebx				;save bump increment
  call	ascii2regs
  pop	ebx
  add	ah,bl				;bump months
bm_22:
  cmp	ah,12
  jbe	bm_30				;jmp if months ok
  inc	edx				;bump year
  sub	ah,12				;adjust months
  jmp	bm_22

bm_30:
  pop	edi				;get storage point
  call	regs_to_date
  ret

;****f* date/ascii2days *
;  ascii2days - convert ascii year,month,day to days since 1970
; INPUTS
;    esi = ptr to ascii string "YYYYMMDD"
; OUTPUT
;    eax = binary days since 1970
  extern regs2days

  [section .text]
ascii2days:
  call	ascii2regs
  call	regs2days
  ret


;****f* date/ascii2regs *
;  ascii2regs - convert ascii year,month,day to bin year,month,day
; INPUTS
;    esi = ptr to ascii string "yyy/mm/dd" without separators
; OUTPUT
;    edx = binary year
;    ah = binary month 1-12
;    al = binary day of month 1-31
  extern ascii_to_dword

  [section .text]
;
ascii2regs:
  lodsd				;get year
  mov	[ayear],eax
  lodsb				;skip /
  lodsw
  mov	[amonth],ax
  lodsb				;skip /
  lodsw
  mov	[aday],ax

  mov	esi,ayear
  call	ascii_to_dword		;get bin year
  push	ecx			;save year
  mov	esi,amonth
  call	ascii_to_dword  	;get bin month
  push	ecx			;save month
  mov	esi,aday
  call	ascii_to_dword  	;get bin day
;
; convert date to days since 1970
;
  mov	al,cl			;position day_of_month
  pop	edx			;get month
  mov	ah,dl			;position month_number
  pop	edx			;get year
  ret

;---------------
  [section .data]
ayear	db	'xxxx',0
amonth	db	'xx',0
aday	db	'xx',0
  [section .text]
;-----------------------------------------------------------
;
; input: edi = store buf
;        eax = days
; output: yyyy/mm/dd in ascii
;
bin_to_date:
  mov	ebx,edi
  mov	ebp,format2
  call	days2ascii
  ret

format2: db '0/1/2',0


;-----------------------------------------------------------
;
;  input:  al = day of month 1-31
;          ah = month number 1-12
;         edx = year
;         edi = storage location for ascii (year,month,day)
; output: ascii stored using ptr edi

regs_to_date:
  push	edi
  call	regs2days	;puts days in eax
  pop	edi
  call	bin_to_date
  ret




  [section .text]
;****f* date/days2ascii *
; NAME
;>1 date
;  days2ascii - convert days to week,day,month, etc.
; INPUTS
;    eax = days since jan 1 1970
;    ebx = buffer for ascii output
;    ebp = format template for ascii output
;    the format string contains two types of data.  Numeric
;    codes "0123456789" and non-numberic ascii characters.
;    Non-numberic characters are passed to the output and
;    not modified.  Any numberic character found is processed
;    as follows:
;      0  -stuff ascii year
;      1  -stuff ascii month
;      2  -stuff ascii day of month
;      6- -stuff short month name
;      6+ -stuff long month name
;      7- -stuff short day of week name
;      7+ -stuff long day of week name
; OUTPUT
;          edi - points at end of output string
;          ebp - points at end of format string
;  Note: the termporary library buffer "lib_buf" is utilized.
;    
;
  extern days2dateregs
;  extern regs2ascii

days2ascii:
  push	ebx		;save buffer for ascii
  call	days2dateregs
  pop	eax
  call	regs2ascii
  ret


;
; The collection of values associated with times and dates
;
struc time
.ct:		resd	1	; raw C time (seconds since the Epoch)
.at:		resd	1	; zone adjusted seconds since last Epoch
.zo:		resd	1	; time zone offset
.zi:		resb	6	; time zone identifier
.tz:		resb	10	; time zone name
; fields set by seconds2bins follow this comment. 
.dc:		resd	1	; days since last Epoch
.sc:		resd	1	; seconds
.mn:		resd	1	; minutes
.hr:		resd	1	; hours
.yr:		resd	1	; year
.mr:		resd	1	; meridian (0 for AM)
.wd:		resd	1	; day of the week (Sunday=0, Saturday=6)
.dy:		resd	1	; day of the month
.mo:		resd	1	; month (one-based)
endstruc

  [section .text]
;----------------------------------------------------------
; regs2ascii - format date
;  input: eax = output buffer for asciiz date string
;         ebp = format string pointer (see below)
;         ebx = year
;          cl = minute
;          ch = second
;          dl = day of month
;          dh = day of week
;         esi = month number
;         edi = hour
;         note: seconds2timeregs,seconds2dateregs can provide
;               year,month,day,hour,minute,sec and day of week
;  output: edi - points at end of output string
;          ebp - points at end of format string
; 
;    the format string contains two types of data.  Numeric
;    codes "0123456789" and non-numberic ascii characters.
;    Non-numberic characters are passed to the output and
;    not modified.  Any numberic character found is processed
;    as follows:
;      0  -stuff ascii year
;      1  -stuff ascii month
;      2  -stuff ascii day of month
;      3  -stuff ascii hour
;      4  -stuff ascii minute
;      5  -stuff ascii second
;      6- -stuff short month name
;      6+ -stuff long month name
;      7- -stuff short day of week name
;      7+ -stuff long day of week name
;      8  -stuff AM/PM
;
;  Note: the termporary library buffer "lib_buf" is utilized.

  extern str_move
  extern lib_buf
;  extern bins2ascii

regs2ascii:			;beware, recursion here
  mov	[lib_buf + time.yr],ebx
  mov	ebx,lib_buf
  mov	[ebx + time.hr],edi
  mov	[ebx + time.mn],cl
  mov	[ebx + time.sc],ch
  mov	[ebx + time.wd],dh
  mov	[ebx + time.dy],dl
  mov	[ebx + time.mo],esi
  mov	cl,0			;preload AM flag
  cmp	edi,12			;is hour over 12
  jbe	stuff1
  mov	cl,1			;get PM flag
stuff1:
  mov	[ebx + time.mr],cl ;save AM/PM flag
  
  mov	edi,eax			;move buffer pointer to edi
  call	bins2ascii
  ret




;----------------------------------------------------------
;>1 date
; bins2ascii - format date
;  input: ebx = time/date data structure pointer
;         ebp = format string pointer
;         edi = output buffer pointer
;  output: edi - points at end of output string
;          ebp - points at end of format string
; 
;    the format string contains two types of data.  Numeric
;    codes "0123456789" and non-numberic ascii characters.
;    Non-numberic characters are passed to the output and
;    not modified.  Any numberic character found is processed
;    as follows:
;      0  -stuff ascii year
;      1  -stuff ascii month
;      2  -stuff ascii day of month
;      3  -stuff ascii hour
;      4  -stuff ascii minute
;      5  -stuff ascii second
;      6- -stuff short month name
;      6+ -stuff long month name
;      7- -stuff short day of week name
;      7+ -stuff long day of week name
;      8  -stuff AM/PM
;      9  -stuff 3 letter zone code

  extern str_move
  extern is_number
  extern dword_to_lpadded_ascii
  extern day_name
  extern month_name

  global bins2ascii
bins2ascii:			;beware, recursion here
  cmp	byte [ebp],0
  je	df_exit		;exit if done
  xor	eax,eax
  mov	al,[ebp]
  inc	ebp
  call	is_number
  jne	df_stuff
  and	al,0fh
  shl	eax,2
  add	eax,fmt_process_tbl
  call	[eax]
  jmp	short bins2ascii
df_stuff:
  stosb
  jmp	short bins2ascii
df_exit:
  ret

  [section .data]
fmt_process_tbl:
  dd	process_year	;0
  dd	process_month	;1
  dd	process_day_of_month ;2
  dd	process_hour	;3
  dd	process_minute	;4
  dd	process_second	;5
  dd	process_month_name ;6
  dd	process_day_name ;7
  dd	process_am_pm	;8
  dd	process_zone	;9
  [section .text]

process_year:
  mov	eax,[ebx + time.yr]
  mov	cl,4		;store 4 digets
  jmp	short pn2

process_month:	;1
  mov	eax,[ebx + time.mo]
  and	eax,0ffh
  jmp	short pn1

process_day_of_month: ;2
  mov	eax,[ebx + time.dy]
  and	eax,0ffh
  jmp	short pn1

process_hour:	;3
  mov	eax,[ebx + time.hr]
  and	eax,0ffh
  jmp	short pn1

process_minute:	;4
  mov	eax,[ebx + time.mn]
  and	eax,0ffh
  jmp	short pn1

process_second:	;5
  mov	eax,[ebx + time.sc]
  and	eax,0ffh
pn1:
  mov	cl,2		;store 4 digets
pn2:
  mov	ch,'0'		;pad char
  push	ebx
  push	ebp
  call	dword_to_lpadded_ascii
  pop	ebp
  pop	ebx
  ret

process_month_name: ;6
  mov	ecx,[ebx + time.mo]
  and	ecx,0ffh
  call	month_name
  jmp	short pn3

process_day_name: ;7
  mov	ecx,[ebx + time.wd]
  and	ecx,0ffh
  call	day_name
pn3:
  mov	al,[ebp]	;get +/- flat
  inc	ebp		;move to next fmt char
  cmp	al,'-'
  je	p_truncate
  call	str_move
  ret
p_truncate:
  movsb
  movsb
  movsb
  ret

process_am_pm:	;8
  mov	ax,'AM'
  mov	cl,[ebx + time.mr]
  or	cl,cl
  jz	pap_stuff
  mov	ax,'PM'
pap_stuff:
  stosw
  ret
  
process_zone:	;9
  lea	esi,[ebx+time.tz]
  call	str_move
  ret

;  str_search - search string for match
; INPUTS
;    esi = input asciiz string terminated with 0-9h
;    edi = string to search, terminated with 0-9h
; OUTPUT
;    carry set if no match
;    no carry if match and registers =
;      esi - points to end of matching string
;      edi - points to end of matched string
;      edx - points to start of matching string
;      ebx - points to start of matched string 
;<
; * ----------------------------------------------
;*******
str_search:
  dec	edi    			;adjust buffer pointer for loop pre-bump
  mov	edx,esi			;save match string start
match_first_char:
  mov esi,edx			;restore match string start
  lodsb
  cmp	al,9
  jbe	notfound		;jmp if no string matches
;get first char from buffer
found1:
  inc	edi			;move forward in scan buffer
;compare string characters
found6:
  cmp al,byte [edi]		;check next char. in buffer
  jne found8			;loop if no match
;first char. matches, set ebx=match point
found2:
  mov ebx,edi
; start of matching loop
found3:
  lodsb			;get next match string char
  cmp	al,9		;=end?
  jbe	found		;done if match
found7:
  inc	edi
  cmp	byte [edi],9
  jbe	notfound	;exit if string not found
  cmp al,byte [edi]	;compare next char in buffer
  jz found3		;loop if match
  mov edi,ebx		;restore buffer scan location before partial match
  jmp	short match_first_char ;go restart match loop
found8:
  cmp byte [edi],9	;check if end of buffer
  ja	found1		;jmp if not end yet
notfound:
  stc
  ret
found:
  inc	edi		;move past match
  clc
  ret

