# nasm is required to compile "cycle"
#
# usage:  make         - compile asmedit executable
#         make clean   - touch all source files
#         make install - install files
#         make release - create release file
#
local = $(shell pwd)
home = $(HOME)
version := $(shell cat VERSION)

#
# hunt for library file, if this fails then set LIBS to file location
# hunt at local dir, parent dir, then at $HOME/.a/
#lib1 = $(shell if test -f asmlib.a ; then echo asmlib.a ; fi)
#lib2 = $(shell if test -f ..//asmlib.a ; then echo ..//asmlib.a ; fi)
#lib3 = $(shell if test -f ../../asmlib.a ; then echo ../../asmlib.a ; fi)
#lib4 = $(shell if test -f /usr/lib/asmlib.a ; then echo /usr/lib/asmlib.a ; fi)

ifeq "$(lib4)" ""
#$(shell echo "$HOME/.a library not found" )
else
LIBS := $(lib4)
endif

ifeq "$(lib3)" ""
#$(shell echo "../../ library not found" )
else
LIBS := $(lib3)
endif
  
ifeq "$(lib2)" ""
#$(shell echo "no parent library")
else
LIBS := $(lib2)
endif

ifeq "$(lib1)" ""
#$(shell echo "no local library")
else
LIBS := $(lib1)
endif

ifeq "$(LIBS)"  ""
LIBS = ./AsmLib/asmlib.a
endif

all:	pre cycle format test

cycle: cycle.o 
	ld -m elf_i386 -e main -o cycle cycle.o $(LIBS)

cycle.o: cycle.asm edit.inc find.inc actions.inc wait_keysig.inc
	nasm -g -felf32 -O99 -o cycle.o cycle.asm


format: format.o 
	ld -m elf_i386 -e main -o format format.o $(LIBS)

format.o: format.asm
	nasm -g -felf32 -O99 -o format.o format.asm


test: test.o 
	ld -m elf_i386 -e main -o test test.o $(LIBS)

test.o: test.asm
	nasm -g -felf32 -O99 -o test.o test.asm


pre:
	touch *.asm
	  @if test -e $(LIBS) ; then \
             echo "asmlib found, compilng cycle" ; \
          else  \
	     echo "asmlib not found, needed by cycle" ; \
             suspend ; \
          fi

#
# the "install" program uses flags
#        -D       create any needed directories
#        -s       strip executables
#        -m 644   set file attributes to 644 octal
install:
	@if test -w /etc/passwd ; \
	then \
	 echo "installing cycle in /usr/bin" ; \
	  install -s cycle /usr/bin ; \
#	 install -D -m 666 cycle.1.gz /usr/share/man/man1/cycle.1.gz ; \
	else \
	  echo "-" ; \
	  echo "Root access needed to install at /usr/bin " ; \
	  echo "aborting install, swithct to root user with su or sudo then retry" ; \
	  fi \

uninstall:
	@if test -w /etc/passwd ; \
	then \
	echo "uninstalling cycle at /usr/bin" ; \
	rm -f /usr/bin/cycle ; \
#	rm -f /usr/share/man/man1/cycle.1.gz ; \
#	echo "uninstalling demo plan in /$HOME/.cycle" ; \
#	rm -f  $(home)/.cycle/plan/demo ; \
#	rm -f  $(home)/.cycle/plan/hints ; \
#	echo "-----------------------------" ; \
#	echo "remove all stored todos? y/n" ; \
#	read AKEY ; \
#	echo "-----------------------------" ; \
#	  if [ $(AKEY) = "y" ] ; then \
#	  echo "removing all todo files" ; \
#	  rm -f $(home)/.cycle/plan/* ; \
#	  rmdir $(home)/.cycle/plan ; \
#	  rm -f $(home)/.cycle/* ; \
#	  rmdir $(home)/.cycle ; \
#	  fi ;  \
	else \
	echo "-" ; \
	echo "Root access needed to uninstall at /usr/bin" ; \
	echo "aborting uninstall, switcht to root user with su or sudo then retry" ; \
	fi 


clean:
	rm -f cycle.o *~
	rm -f release
	-rmdir release

doc:
	../txt2man -t cycle cycle.txt | gzip -c > cycle.1.gz 

release: tar deb rpm

tar:
	strip cycle
	if [ ! -e "../release" ] ; then mkdir ../release ; fi
	tar cfz ../release/cycle.tar.gz -C .. cycle

deb:
#	sudo checkinstall -D --pkgversion=$(version) --pakdir=../release --maintainer=jeff@linuxasmtools.net -y

rpm:
#	sudo checkinstall -R --pkgversion=$(version) --pakdir=../release -y --pkgname=cycle
#	sudo chown --reference Makefile ../release/cycle*
#	rm -f backup*





