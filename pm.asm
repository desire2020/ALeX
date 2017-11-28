%define CURRENT_SIZE 512
%define STACK_SIZE 256
%include "x86_32_protected_mode.lib"
org		0100h
jmp __start_16bit
[SECTION .gdt]
;                  Base,            Border,                                Attribute
GDTBase:
Descriptor            0,                 0,                                        0
DescriptorNormal:
Descriptor            0,            0ffffh,                     DataSegmentReadWrite
Descriptor16Bit:
Descriptor            0,            0ffffh,                             CodeSegmentX
Descriptor32Bit:
Descriptor            0, CodeSegBit32Len-1,                      CodeSegmentX + DA32
DescriptorData:
Descriptor            0,           DataLen,                             CodeSegmentX
DescriptorStack:
Descriptor            0,        TopOfStack,       DataSegmentReadWriteVisited + DA32
DescriptorTest:
Descriptor     0500000h,            0ffffh,                     DataSegmentReadWrite
DescriptorVideo:
Descriptor      0B8000h,            0ffffh,                     DataSegmentReadWrite

GdtLength          equ $ - GDTBase

GdtPointer          dw GdtLength - 1 ; Border
                    dd 0             ; Base (need to be calculated after, this is just an initialization)

SelectorNormal     equ DescriptorNormal - GDTBase
SelectorCode16     equ Descriptor16Bit - GDTBase
SelectorCode32     equ Descriptor32Bit - GDTBase
SelectorData       equ DescriptorData - GDTBase
SelectorStack      equ DescriptorStack - GDTBase
SelectorTest       equ DescriptorTest - GDTBase
SelectorVideo      equ DescriptorVideo - GDTBase

[SECTION .data1]
ALIGN 32
[BITS 32]
__data_segment:
backup_register_sp       dw 0
on_success_pm            db "ALeX Version 0.0.0 alpha", 0
OffsetOnSuccessPM       equ on_success_pm - $$
write_test               db 19H, 97H, 03H, 06H, 13H, 02H, 00H
OffsetWriteTest         equ write_test - $$

DataLen                 equ $ - __data_segment

[SECTION .gs]
ALIGN 32
[BITS 32]
__stack_space:
times STACK_SIZE db 0

TopOfStack              equ $ - __stack_space - 1


[SECTION .s16]
[BITS 16]
__start_16bit:
; Real Mode Initialization
mov     ax, cs
mov     ds, ax
mov     es, ax
mov     ss, ax
mov     sp, 0100h

mov     [__switch_back_to_real_mode + 3], ax
mov     [backup_register_sp], sp

; 16 Bit Code Descriptor Initialization
mov     ax, cs
movzx   eax, ax
shl     eax, 4
add     eax, __start_16bit_ret
mov     word[Descriptor16Bit + 2], ax
shr     eax, 16
mov     byte[Descriptor16Bit + 4], al
mov     byte[Descriptor16Bit + 7], ah

; 32 Bit Code Descriptor Initialization
xor     eax, eax
mov     ax, cs
shl     eax, 4
add     eax, __start_32bit
mov     word[Descriptor32Bit + 2], ax
shr     eax, 16
mov     byte[Descriptor32Bit + 4], al
mov     byte[Descriptor32Bit + 7], ah

; Data Segment Descriptor Initialization
xor     eax, eax
mov     ax, cs
shl     eax, 4
add     eax, __data_segment
mov     word[DescriptorData + 2], ax
shr     eax, 16
mov     byte[DescriptorData + 4], al
mov     byte[DescriptorData + 7], ah

; Stack Segment Descriptor Initialization
xor     eax, eax
mov     ax, cs
shl     eax, 4
add     eax, __stack_space
mov     word[DescriptorStack + 2], ax
shr     eax, 16
mov     byte[DescriptorStack + 4], al
mov     byte[DescriptorStack + 7], ah

; Preparing for GDTR
xor     eax, eax
mov     ax, ds
shl     eax, 4
add     eax, GDTBase
mov     dword[GdtPointer + 2], eax

; Load GDTR
lgdt    [GdtPointer]

; Close Interrupt
cli

; Enable Address A20
in      al, 01010010b
or      al, 00000010b
out     01010010b, al

; Preparing for mode switching
mov     eax, cr0
or      eax, 1
mov     cr0, eax

; Switch to protected mode
jmp     dword SelectorCode32:0

__ret_16bit:
mov     ax, cs
mov     ds, ax
mov     es, ax
mov     ss, ax

mov     sp, [backup_register_sp]
in      al, 01010010b
and     al, 11111101b
out     01010010b, al

sti

mov     ax, 4c00h
jmp     $

[SECTION .s32]
[BITS 32]

print_al:
push    ecx
push    edx

mov     ah, 0Ch
mov     dl, al
shr     al, 4
mov     ecx, 2

.loop_start:
    and     al, 01111b
    cmp     al, 9
    ja      .loop_hex
    add     al, '0'
    jmp     .loop_print
.loop_hex:
    sub     al, 0Ah
    add     al, 'A'
.loop_print:
    mov     [gs:edi], ax
    add     edi, 2
.loop_end:
    mov     al, dl
    loop    .loop_start
    add     edi, 2

pop     edx
pop     ecx

ret

pseudo_println:
push    eax
push    ebx
mov     eax, edi
mov     bl, 160
div     bl
and     eax, 0FFh
inc     eax
mov     bl, 160
mul     bl
mov     edi, eax
pop     ebx
pop     eax

ret

stack_read:
xor     esi, esi
mov     ecx, 8

.loop_start:
    mov     al, [es:esi]
    call    print_al
    inc     esi
    loop    .loop_start

call pseudo_println

ret

stack_write:
push    esi
push    edi
xor     esi, esi
xor     edi, edi
mov     esi, OffsetWriteTest
cld
.loop_start:
    lodsb
    test    al, al
    jz      .loop_end
    mov     [es:edi], al
    inc     edi
    jmp     .loop_start
.loop_end:
pop     edi
pop     esi

ret

__start_32bit:
mov     ax, SelectorData
mov     ds, ax
mov     ax, SelectorTest
mov     es, ax
mov     ax, SelectorVideo
mov     gs, ax
mov     ax, SelectorStack
mov     ss, ax

mov     esp, TopOfStack

mov     ah, 0Ch
xor     esi, esi
xor     edi, edi
mov     esi, OffsetOnSuccessPM
mov     edi, (80 * 10 + 0) * 2
cld

.loop_start:
    lodsb
    test    al, al
    jz      .loop_end
    mov     [gs:edi], ax
    add     edi, 2
    jmp     .loop_start

.loop_end:
    call    pseudo_println

    call    stack_read
    call    stack_write
    call    stack_read

    jmp     SelectorCode16:0
jmp $

CodeSegBit32Len   equ $ - __start_32bit

[SECTION .s16code]
ALIGN   32
[BITS   16]
__start_16bit_ret:
mov     ax, SelectorNormal
mov     ds, ax
mov     es, ax
mov     fs, ax
mov     gs, ax
mov     ss, ax

mov     eax, cr0
and     al, 11111110b
mov     cr0, eax

__switch_back_to_real_mode:
    jmp     0:__ret_16bit ; "0" will be edited in the initialization part.
                          ; Also, this proves that x86 is a Von Neuuman Machine.
ALIGN   16
