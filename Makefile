# GASM: Gopher Assembly (i386 Edition)

all: gasm

gasm: gasm.o
	ld -m elf_i386 gasm.o -o gasm

gasm.o: gasm.asm
	nasm -f elf32 gasm.asm -o gasm.o

clean:
	rm -f gasm gasm.o

run: gasm
	./gasm content
