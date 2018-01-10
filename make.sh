nasm boot.asm -o boot.bin
nasm loader.asm -o pm-x86.sys
# gcc -m32 xxx.c -c -o alex.o
nasm -f elf32 kernel.asm -o alex.o
ld -m elf_i386 -s -o alex.sys alex.o -Ttext 0x30400 