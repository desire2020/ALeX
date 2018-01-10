
; 编译链接方法
; [root@XXX XXX]# nasm -f elf kernel.asm -o kernel.o
; [root@XXX XXX]# ld -s -Ttext 0x30400 -o kernel.bin kernel.o
; [root@XXX XXX]# 
[section .data]
char0:       db      'A'
[section .text]	; 代码在此

global _start	; 导出 _start

_start:	; 跳到这里来的时候，我们假设 gs 指向显存
	mov	ah, 0Fh				; 0000: 黑底    1111: 白字
	mov	al, [char0]
	mov	[gs:((80 * 1 + 39) * 2)], ax	; 屏幕第 1 行, 第 39 列。
    inc al
    mov [char0], al
	jmp	_start
