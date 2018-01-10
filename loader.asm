org     0100h

%include "memalloc.lib"

jmp     __start
%include "FAT12.lib"
%include "x86_32_protected_mode.lib"

; GDT

GDTBase:
NullDescriptor:			Descriptor			0,			0,			0
Code32Descritor:		Descriptor			0,	  0fffffh,	DA32|CodeSegmentX|DA32Limit
Data32Descritor:		Descriptor 			0,	  0fffffh,  DA32|DataSegmentReadWrite|DA32Limit
GraphicsDescriptor:		Descriptor 	  0b8000h,	   0ffffh, 	DataSegmentReadWrite|DPL_3

GdtLength				equ	$ - GDTBase
GdtPointer				dw	GdtLength - 1
						dd  BaseOfLoaderPhy + GDTBase

SelectorCode32			equ	Code32Descritor - GDTBase
SelectorData32			equ	Data32Descritor - GDTBase
SelectorGraphics		equ	GraphicsDescriptor - GDTBase + RPL_3

; Code Segment
__start:
mov     ax, cs
mov     ds, ax
mov     es, ax
mov     ss, ax
mov     sp, BaseOfKernelStack

mov     dh, 0                                     ;
call    print_idx                                 ; print_idx(0)

; MemCheck
mov		ebx, 0									  ;	$ebx = 0
mov		di, bits16_MemoryCheckBuffer			  ;	[$es:$di] = MemoryCheckBuffer
.loop_memcheck:								      ; while True:
	mov		eax, 0E820h							  ; 	$eax = 0000E820h
	mov		ecx, 20								  ;		$ecx = size(ARDS)
	mov		edx, 0534D4150h						  ; 	$edx = int32("SMAP")
	int		15h								 	  ; 	try: sys.syscall(0x15)
	jc		.loop_memcheck_fail					  ;		catch(...): throw MemcheckFailureException()
	add		di, 20								  ; 	[$es:$di] += [:20]
	inc		dword [bits16_dMCRNumber]			  ; 	++MCRNumber
	cmp		ebx, 0								  ; 	if $ebx != 0:
	jne		.loop_memcheck						  ;			continue
	jmp		.loop_memcheck_done					  ;		else: break
.loop_memcheck_fail:							  ;	def Handler.MemcheckFailureException()
												  ;		global MCRNumber
	mov		dword [bits16_dMCRNumber], 0		  ;		MCRNumber = 0
.loop_memcheck_done: 

xor     ah, ah
xor     dl, dl
int     13h                                       ; sys.floppy.call(sys.floppy.reset)

mov     word [wSectorNo], SectorIdxOfRoot
                                                  ; idx_of_root = SectorIdxOfRoot
.loop_start:                                      ; while True:
    cmp     word [wCounterRootSec], 0             ;     if idx_of_root == 0:
    jz      .loop_kernel_not_found                ;         throw KernelNotFoundException()
    dec     word [wCounterRootSec]                ;     idx_of_root -= 1
    mov     ax, BaseOfKernel                      ;     $es = BaseOfKernel
    mov     es, ax                                ;     base = BaseOfKernel
    mov     bx, OffsetOfKernel                    ;     offset = OffsetOfKernel
    mov     ax, [wSectorNo]                       ;     target_start = target_sector
    mov     cl, 1                                 ;     target_limit = 1
    call    read_sector                           ;     read_sector(sys.memory[base:offset],
                                                  ;                 target_start,
                                                  ;                 target_limit)
    mov     si, KernelFileName                    ;     $ds, $si = BaseOfBooter, KernelFileName
    mov     di, OffsetOfKernel                    ;     $es, $di = BaseOfKernel, OffsetOfKernel
    cld                                           ;     sys.instructions.lodsb.mode.set(Forward)

    mov     dx, 10h                               ;     $dx = 0x10
.loop_seek_kernel:                                ;     while True:
    cmp     dx, 0                                 ;         if $dx != 0:
    jz      .loop_next_sector                     ;             # This means the sector is not fully checked.
    dec     dx                                    ;             $dx -= 1

    mov     cx, 11                                ;             $cx = 11
.loop_filename_check:                             ;             while True:
    cmp     cx, 0                                 ;                 if $cx == 0:
    jz      .loop_kernel_found                    ;                     throw KernelFoundSignal()
    dec     cx                                    ;                 $cx -= 1
    lodsb                                         ;                 $al = sys.memory[$ds + $si]; $si += 1
    cmp     al, byte [es:di]                      ;                 if $al == sys.memory[$es + $di]:
    jz      .loop_continue_check                  ;                     throw NameMatchSignal()
                                                  ;                 else:
    jmp     .loop_skip_current                    ;                     throw NameMismatchException()
.loop_next_sector:                                ;         else:
    add     word [wSectorNo], 1                   ;             target_sector += 1
    jmp     .loop_start                           ;             break
.loop_continue_check:
    inc     di
    jmp     .loop_filename_check
.loop_skip_current:                               ; def Handler.NameMismatchException() @contextual:
    and     di, 0FFE0h                            ;     $di = ($di >> 5) << 5
    add     di, 20h                               ;     $di += 32
    mov     si, KernelFileName                    ;     $ds, $si = BaseOfBooter, KernelFileName
    jmp     .loop_seek_kernel                     ;     break
.loop_kernel_not_found:                           ; def Handler.KernelNotFoundException():
    mov     dh, 2                                 ;
    call    print_idx                             ;     print_idx(2)
    jmp     $                                     ;     halt()
.loop_kernel_found:                               ; def.Handler.KernelFoundSignal():
    mov     ax, RootDirSectors                    ;     global KernelSize
    and     di, 0FFF0h                            ;     $di = ($di >> 4) << 4

	push	eax									  ;
	mov		eax, [es: di + 01Ch]				  ;		
	mov		dword [dKernelSize], eax 			  ; 	KernelSize = sys.memory[$es:$di+01Ch]
	pop		eax

    add     di, 01Ah                              ;     $di += 26
    mov     cx, word [es:di]                      ;     $cx = sys.memory[$es:$di]
    push    cx                                    ;     sys.stack.write($cx)

    add     cx, ax
    add     cx, OffsetSectorNo                    ;     $cx += RootDirSectors + OffsetSectorNo    
    mov     ax, BaseOfKernel                      ;     
    mov     es, ax                                ;     $es = BaseOfKernel
    mov     bx, OffsetOfKernel                    ;     $bx = OffsetOfKernel
    mov     ax, cx                                ;     $ax = $cx

.loop_loop_read_kernel:                           ;     while True:
    push    ax
    push    bx
    mov     ah, 0Eh                               ;         write(sys.graphics, '.')
    mov     al, '.'
    mov     bl, 0Fh
    int     10h
    pop     bx
    pop     ax      
    
    mov     cl, 1
    call    read_sector                           ;         read_sector(sec_base = $ax, sec_num = 1, target_seg=[BaseOfKernel: OffsetOfKernel])

    pop     ax                                    ;         sys.stack.read_and_pop($ax)
    call    get_FAT_entry                         ;         $ax = get_FAT_entry(sector_no = $ax)

    
    cmp     ax, 0FFFh                             ;         if $ax == 0FFFh:
    jz      .loop_read_kernel_done                ;             break
    push    ax                                    ;         sys.stack.write($ax)
    add     ax, RootDirSectors                    ;         $ax += RootDirSectors
    add     ax, OffsetSectorNo                    ;         $ax += OffsetSectorNo
    add     bx, [FAT12_BytesPerSector]            ;         $bx = OffsetOfKernel + FAT12_BytesPerSector
    jmp     .loop_loop_read_kernel

.loop_read_kernel_done:
	call	kill_motor

    mov     dh, 1                                 
    call    print_idx                             ;     print_idx(1)

	lgdt	[GdtPointer]
	
	cli

	in      al, 92h
	or      al, 00000010b
	out     92h, al

	; Preparing for mode switching
	mov     eax, cr0
	or      eax, 1
	mov     cr0, eax

    jmp     dword SelectorCode32:(BaseOfLoaderPhy+__start32) ;     sys.unsafe.goto(BaseOfKernel:OffsetOfKernel) 
					                             		     ;     print_idx(3)
    jmp     $
; Variable Segment
wCounterRootSec             dw RootDirSectors
wSectorNo                   dw 0
bIsOdd                      db 0
dKernelSize					dd 0

KernelFileName              db "ALEX    SYS", 0

MessageLength              equ 15

MessageBase:
MessageBootStart            db "Loading        " ; String index 0
MessageKernelReady          db "Kernel ready.  " ; String index 1
MessageKernelMiss           db "Kernel missing." ; String index 2
MessageDebug                db "Real Mode back." ; String index 3

; Utility Functions Segment
print_idx:                                        ; def print_idx(mess_idx in $dh):
mov     ax, MessageLength                         ;     $ax = MessageLength
mul     dh                                        ;     $ax *= mess_idx
add     ax, MessageBase                           ;     $ax += MessageBase
mov     bp, ax                                    ;     $es, $bp = BaseOfLoader, $ax
mov     ax, ds
mov     es, ax
mov     cx, MessageLength                         ;     $cx = MessageLength
mov     ax, 01301h                                ;     $ax = sys.real_mode.syscall_idx("out_str")
mov     bx, 0007h                                 ;     $bx = sys.real_mode.VGA(background = "Black",
                                                  ;                             text = "White")
mov     dl, 0                                     ;
int     10h                                       ;     sys.real_mode.syscall($ax, $bx, ($es, $bp))
ret                                               ;     return

read_sector:                                      ; def read_sector(sec_base in $ax, sec_num in $cl, target_seg in [$es:$bx]):
push    bp                                        ; """
mov     bp, sp                                    ; @params: load sec_cum sectors that start from sec_base into target_seg.
sub     esp, 2                                    ; """

mov     byte [bp - 2], cl                         ;     to_be_loaded_num = sec_num
push    bx
mov     bl, [FAT12_SectorPerTrack]
div     bl                                        ;     $al, $ah = sec_base / FAT12_SectorPerTrack, sec_base % FAT12_SectorPerTrack

inc     ah                                        ;     $ah += 1
mov     cl, ah                                    ;     $cl = $ah
mov     dh, al                                    ;     $dh = $al
shr     al, 1                                     ;     $al >>= 1
mov     ch, al                                    ;     $ch = $al
and     dh, 1                                     ;     $dh &= 1

pop     bx

mov     dl, [FAT12_DriveIndex]                    ;     $dl = FAT12_DriveIndex
.loop_retry:
    mov     ah, 2                                 ;     sys.floppy.set_mode("read")
    mov     al, byte [bp - 2]                     ;     sys.floppy.set_lim(to_be_loaded_num)
                                                  ;
    int     13h                                   ;     while sys.floppy.not_valid_op():
    jc      .loop_retry                           ;         sys.floppy.move()

add     esp, 2
pop     bp

ret                                               ;     return

get_FAT_entry:                                    ; def get_FAT_entry(sector_no in $ax) -> int in $ax:
push    es
push    bx
push    ax
                                                  ;     global is_odd
mov     ax, BaseOfKernel
sub     ax, 0100h
mov     es, ax                                    ;     $es = BaseOfKernel - 0100h
pop     ax

mov     byte [bIsOdd], 0                          ;     is_odd = False

mov     bx, 3
mul     bx                                        ;     _, $ax = sys.dualreg_unstack(ax * 3)
mov     bx, 2
div     bx                                        ;     $dx, $ax = $ax % 2, $ax / 2
cmp     dx, 0
jz      .is_even                                  ;     if $dx != 0:
mov     byte [bIsOdd], 1                          ;         is_odd = True
.is_even:
    xor     dx, dx                                ;
    mov     bx, [FAT12_BytesPerSector]            ;     $bx = FAT12_BytesPerSector
    div     bx                                    ;     $ax, $dx = $ax / $bx, $ax % $bx
    push    dx

    xor     bx, bx                                ;     $bx = 0
    add     ax, SectorBaseFAT1                    ;     $ax += SectorBaseFAT1
    mov     cl, 2
    call    read_sector                           ;     read_sector(sec_base=$ax, sec_num=2, target_seg=sys.memory[$es:$bx])

    pop     dx
    add     bx, dx                                ;     $bx += $dx

    mov     ax, [es:bx]                           ;     $ax = sys.memory[$es:$bx]
    cmp     byte [bIsOdd], 1                      ;     if is_odd:
    jnz     .is_even_branch0
    shr     ax, 4                                 ;         $ax >>= 4

.is_even_branch0:
    and     ax, 0000111111111111b                 ;     $ax &= 0000111111111111b

pop     bx
pop     es

ret                                               ;     return $ax

kill_motor:										  ; def sys.floppy.halt():
push	dx
mov		dx, 03F2h
mov		al, 0
out		dx, al									  ;		sys.send_message(port=03F2h, bytecode=0)
pop		dx
ret												  ;		return

[SECTION .s32]

ALIGN	32

[BITS	32]

__start32:
mov		ax, SelectorGraphics
mov		gs, ax

mov		ax, SelectorData32
mov		ds, ax
mov		es, ax
mov		fs, ax
mov		ss, ax
mov  	esp, TopOfStack

push	bits32_MemchkTableTitle
call	print
add		esp, 4

call	display_memory_info
call	setup_paging

mov 	ah, 0Fh
mov		al, 'P'
mov		[gs:((80 * 0 + 39) * 2)], ax

call	init_kernel

jmp		SelectorCode32:KernelEntryAddrPhy

print_al:                  ;   def print_al(number in $al, ref pos in $ebx)
push    ecx
push    edx
push    edi

mov     edi, [bits32_dCurrentPos]

mov     ah, 0Fh
mov     dl, al
shr     al, 4
mov     ecx, 2

.begin:
    and     al, 01111b
    cmp     al, 9
    ja      .1
    add     al, '0'
    jmp     .2
.1:
    sub     al, 0Ah
    add     al, 'A'
.2:
    mov     [gs:edi], ax
    add     edi, 2

mov     al, dl
loop    .begin

mov     [bits32_dCurrentPos], edi

pop     edi
pop     edx
pop     ecx

ret

print_int:
mov     eax, [esp + 4]
shr     eax, 24
call    print_al

mov     eax, [esp + 4]
shr     eax, 16
call    print_al

mov     eax, [esp + 4]
shr     eax, 8
call    print_al

mov     eax, [esp + 4]
call    print_al

mov     ah, 07h
mov     al, 'h'
push    edi
mov     edi, [bits32_dCurrentPos]
mov     [gs:edi], ax
add     edi, 4
mov     [bits32_dCurrentPos], edi
pop     edi

ret

print:
push    ebp
mov     ebp, esp
push    ebx
push    esi
push    edi

mov     esi, [ebp + 8]
mov     edi, [bits32_dCurrentPos]
mov     ah, 0Fh
.1:
    lodsb
    test    al, al
    jz      .2
    cmp     al, 0Ah
    jnz     .3
    push    eax
    mov     eax, edi
    mov     bl, 160
    div     bl
    and     eax, 0FFh
    inc     eax
    mov     bl, 160
    mul     bl
    mov     edi, eax
    pop     eax
    jmp     .1
.3:
    mov     [gs:edi], ax
    add     edi, 2
    jmp     .1
.2:
    mov     [bits32_dCurrentPos], edi

pop     edi
pop     esi
pop     ebx
pop     ebp
ret

println:
push    ebx
push    eax
mov     eax, [bits32_dCurrentPos]
mov     bl, 160
div     bl
and     eax, 0FFh
inc     eax
mov     bl, 160
mul     bl
mov     [bits32_dCurrentPos], eax
pop     eax
pop     ebx
ret

memcpy:
push    ebp
mov     ebp, esp

push    esi
push    edi
push    ecx

mov     edi, [ebp + 8]
mov     esi, [ebp + 12]
mov     ecx, [ebp + 16]

.1:
    cmp     ecx, 0
    jz      .2

    mov     al, [ds:esi]
    inc     esi

    mov     byte[es:edi], al
    inc     edi

    dec     ecx
    jmp     .1

.2:
    mov     eax, [ebp + 8]

pop     ecx
pop     edi
pop     esi
mov     esp, ebp
pop     ebp

ret

display_memory_info:
push	esi
push	edi
push	ecx

mov		esi, bits32_MemoryCheckBuffer
mov		ecx, [bits32_dMCRNumber]
.loop:
	mov		edx, 5
	mov		edi, bits32_ARDStruct
.1:
	push	dword [esi]
	call	print_int
	pop		eax
	stosd
	add		esi, 4
	dec		edx
	cmp		edx, 0
	jnz		.1
	call	println
	cmp		dword [bits32_ARDStruct_Type], 1
	jne		.2
	mov		eax, [bits32_ARDStruct_BaseAddrLow]
	add		eax, [bits32_ARDStruct_LengthLow]
	cmp		eax, [bits32_dMemorySize]
	jb		.2
	mov		[bits32_dMemorySize], eax
.2:
	loop	.loop

	call	println
	push	bits32_MemorySizeTitle
	call	print
	add		esp, 4

	push	dword [bits32_dMemorySize]
	call	print_int
	add		esp, 4

pop		ecx
pop		edi
pop		esi
ret

setup_paging:
	xor		edx, edx
	mov		eax, [bits32_dMemorySize]
	mov		ebx, 400000h
	div		ebx
	mov		ecx, eax
	jz		.exactly_fit
	inc		ecx
.exactly_fit:
	push	ecx
	mov		ax, SelectorData32
	mov		es, ax
	mov		edi, PageDirBase
	xor		eax, eax
	mov		eax, PageTableBase | PageExist | PageUser | PageReadWriteExecute
.1:
	stosd
	add		eax, 4096
	loop	.1
	
	pop		eax
	mov		ebx, 1024
	mul		ebx
	mov		ecx, eax
	mov		edi, PageTableBase
	xor		eax, eax
	mov		eax, PageExist | PageUser | PageReadWriteExecute
.2:
	stosd
	add		eax, 4096
	loop	.2

	mov		eax, PageDirBase
	mov		cr3, eax
	mov		eax, cr0
	or		eax, 80000000h
	mov		cr0, eax
	jmp		short .3
.3:
	nop

ret

init_kernel:
xor		esi, esi
mov		cx, word [BaseOfKernelPhy + 2Ch]
movzx 	ecx, cx
mov		esi, [BaseOfKernelPhy + 1Ch]
add		esi, BaseOfKernelPhy
.loop_start:
	mov		eax, [esi + 0]
	cmp		eax, 0
	jz		.loop_skip_current
	push	dword [esi + 010h]
	mov		eax, [esi + 04h]
	add		eax, BaseOfKernelPhy
	push	eax
	push	dword [esi + 08h]
	call	memcpy
	add		esp, 12
.loop_skip_current:
	add		esi, 020h
	dec		ecx
	jnz		.loop_start

ret
[SECTION .data1]

ALIGN	32

__data:

bits16_MemoryCheckBuffer:		times	256	db	0
bits32_MemoryCheckBuffer		equ		BaseOfLoaderPhy + bits16_MemoryCheckBuffer
bits16_dMCRNumber:				dd		0
bits32_dMCRNumber				equ		BaseOfLoaderPhy + bits16_dMCRNumber
bits16_dCurrentPos:				dd		(80 * 6 + 0) * 2
bits32_dCurrentPos 				equ		BaseOfLoaderPhy + bits16_dCurrentPos
bits16_dMemorySize:				dd		0
bits32_dMemorySize 				equ		BaseOfLoaderPhy + bits16_dMemorySize

bits16_ARDStruct:
bits16_ARDStruct_BaseAddrLow:	dd		0
bits16_ARDStruct_BaseAddrHigh:	dd		0
bits16_ARDStruct_LengthLow:		dd		0
bits16_ARDStruct_LengthHigh:	dd  	0
bits16_ARDStruct_Type:			dd		0
bits32_ARDStruct				equ		BaseOfLoaderPhy + bits16_ARDStruct
bits32_ARDStruct_BaseAddrLow	equ		BaseOfLoaderPhy + bits16_ARDStruct_BaseAddrLow
bits32_ARDStruct_BaseAddrHigh	equ		BaseOfLoaderPhy + bits16_ARDStruct_BaseAddrHigh
bits32_ARDStruct_LengthLow		equ		BaseOfLoaderPhy + bits16_ARDStruct_LengthLow
bits32_ARDStruct_LengthHigh		equ  	BaseOfLoaderPhy + bits16_ARDStruct_LengthHigh
bits32_ARDStruct_Type			equ		BaseOfLoaderPhy + bits16_ARDStruct_Type

bits16_MemchkTableTitle:		db 		"BaseAddrL BaseAddrH LengthLow LengthHigh   Type", 0Ah, 0
bits16_MemorySizeTitle:			db 		"RAM size:", 0
bits32_MemchkTableTitle			equ		BaseOfLoaderPhy + bits16_MemchkTableTitle
bits32_MemorySizeTitle			equ		BaseOfLoaderPhy + bits16_MemorySizeTitle

StaticStack:					times 	1000h		db 	0
TopOfStack:						equ		BaseOfLoaderPhy + $