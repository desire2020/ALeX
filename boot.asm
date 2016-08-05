	org 07c00h
	
StackBase		equ		07c00h
LoaderBase		equ 	09000h
LoaderOffset	equ 	00100h
RootDirSectors	equ		14
RootDirSecNo	equ		19

	jmp short _start
	nop

; FAT12 Descriptor
	BS_OEMNAME		DB 	"Sui.2020"
	BPB_BytsPerSec	DW	512
	BPB_SecPerClus	DB	1
	BPB_RsvdSecCnt	DW	1
	BPB_NumFATs		DB	2
	BPB_RootEntCnt	DW	224
	BPB_TotSec16	DW	2880
	BPB_Media		DB	0xF0
	BPB_FATSz16		DW	9
	BPB_SecPerTrk	DW	18
	BPB_NumHeads	DW	2
	BPB_HiddSec		DD	0
	BPB_TotSec32	DD 	0
	BS_DrvNum 		DB	0
	BS_Reserved1	DB	0
	BS_BootSig		DB	29h
	BS_VolID		DD	0
	BS_VolLab		DB	"SuiX Beetho"
	BS_FileSysType	DB	"FAT12   "

_start:
	mov		ax, cs
	mov		ds, ax
	mov		es, ax
	mov		ss, ax
	mov		sp, StackBase
	
	mov		ax, 0600h
	mov		bx, 0700h
	mov		cx, 0
	mov		dx, 0184fh
	int		10h
;	DispStr(0)
	mov		dh, 0
	call	DispStr
;	Reset Drive A
	xor		ah, ah
	xor		dl, dl
	int		13h
	
_start_file_detection:
	mov		word [wSectorNo], RootDirSecNo
_search_in_root_dir_begin:
	cmp		word [wRootDirSz], 0
	jz		_not_found
	dec		word [wRootDirSz]
	mov		ax, LoaderBase
	mov		es, ax
	mov		bx, LoaderOffset
;	ReadSector(wSectorNo, 1)
	mov		ax, [wSectorNo]
	mov		cl, 1
	call	ReadSector
	
	mov		si, Loader
	
;Var

wRootDirSz			dw	RootDirSectors
wSectorNo			dw	0
isOdd				db	0
LoaderFileName		db	"LOADER	 BIN", 0
MessageLength		equ	16
BootMessage			db 	"Booter in queue."
Message1			db 	"Booter finished."
Message2			db	"Loader not found"

;Functions

;DispStr(int idx : register dh) {
DispStr:
	mov		ax, MessageLength
	mul		dh
	add		ax, BootMessage
	mov		bp, ax
	mov		ax, ds
	mov		es, ax
	mov		cx, MessageLength
	mov		ax, 01301h
	mov		bx, 0007h
	mov		dl, 0
	int		10h
	ret
	
;ReadSector(int sec_start : register ax; int sec_total : register cl) {
ReadSector:
	push	bp
	mov		bp, sp
	sub		esp, 2
	mov		byte [bp - 2], cl
	push	bx
	mov		bl, [BPB_SecPerTrk]
	div		bl
	inc		ah
	mov		cl, ah
	mov		dh, al
	shr		al, 1
	mov		ch, al
	and		dh, 1
	pop		bx
	mov 	dl, [BS_DrvNum]
.GoOnReading:
	mov		ah, 2
	mov		al, byte [bp-2]
	int		13h
	jc		.GoOnReading
;	while(!(syscall(0x13)	
	add		esp, 2
	pop		bp
	
	ret
	