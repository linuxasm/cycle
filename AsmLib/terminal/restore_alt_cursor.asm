
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


  [section .text align=1]

  [section .text]

  extern alt_cursor
  extern restore_cursor_from
    
;>1 terminal
;   restore_alt_cursor - restore cursor for alt window
; INPUTS
;   none
; OUTPUT
;   none
; NOTES
;    source file: restore_alt_cursor.asm
;
;    This function assumes we have switched to alt-window
;    and restores the saved alt window cursor, if no previous
;    cursor has been saved, it puts cursor at location 1,1
;<
;------------------------------------------------------------------
  global restore_alt_cursor
restore_alt_cursor:
  mov	esi,alt_cursor
  call	restore_cursor_from
  ret

  [section .text]
