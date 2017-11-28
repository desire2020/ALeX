org     07c00h

BaseOfStack             equ 07c00h
BaseOfLoader            equ 09000h
OffsetOfLoader          equ 0100h
SectorOccupiedByRoot    equ 14
SectorBaseOfRoot        equ 19
SectorBaseFAT1          equ 1
OffsetSectorNo          equ 1 + 2 * 9 - 2  ; SectorBase + NumFATs * FATSize - 2


jmp     short __start
%include "FAT12.lib"


; Code Segment
__start:
mov     ax, cs
mov     ds, ax
mov     es, ax
mov     ss, ax
mov     sp, BaseOfStack

xor     ah, ah
xor     dl, dl
int     13h                                       ; sys.floppy.call(sys.floppy.reset)

mov     word [word_target_sector], SectorBaseOfRoot
                                                  ; idx_of_root = SectorBaseOfRoot
.loop_start:                                      ; while True:
    cmp     word [word_idx_of_root_sec], 0        ;     if idx_of_root == 0:
    jz      .loop_loader_not_found                ;         throw LoaderNotFoundException()
    dec     word [word_idx_of_root_sec]           ;     idx_of_root -= 1
    mov     ax, BaseOfLoader                      ;     $es = BaseOfLoader
    mov     es, ax                                ;     base = BaseOfLoader
    mov     bx, OffsetOfLoader                    ;     offset = OffsetOfLoader
    mov     ax, [word_target_sector]              ;     target_start = target_sector
    mov     cl, 1                                 ;     target_limit = 1
    call    read_sector                           ;     read_sector(sys.memory[base:offset],
                                                  ;                 target_start,
                                                  ;                 target_limit)
    mov     si, LoaderFileName                    ;     $ds, $si = BaseOfBooter, LoaderFileName
    mov     di, OffsetOfLoader                    ;     $es, $di = BaseOfLoader, OffsetOfLoader
    cld                                           ;     sys.instructions.lodsb.mode.set(Forward)

    mov     dx, 10h                               ;     $dx = 0x10
.loop_seek_loader:                                ;     while True:
    cmp     dx, 0                                 ;         if $dx != 0:
    jz      .loop_next_sector                     ;             # This means the sector is not fully checked.
    dec     dx                                    ;             $dx -= 1

    mov     cx, 11                                ;             $cx = 11
.loop_filename_check:                             ;             while True:
    cmp     cx, 0                                 ;                 if $cx == 0:
    jz      .loop_loader_found                    ;                     throw LoaderFoundInterruption()
    dec     cx                                    ;                 $cx -= 1
    lodsb                                         ;                 $al = sys.memory[$ds + $si]; $si += 1
    cmp     al, byte [es:di]                      ;                 if $al == sys.memory[$es + $di]:
    jz      .loop_continue_check                  ;                     throw NameMatchInterruption()
                                                  ;                 else:
    jmp     .loop_skip_current                    ;                     throw NameMismatchException()
.loop_next_sector:                                ;         else:
    inc     word [word_target_sector]             ;             target_sector += 1
    jmp     .loop_start                           ;             break
.loop_continue_check:                             ; def Handler.NameMatchInterruption() @contextual:
    inc     di                                    ;     $di += 1
    jmp     .loop_filename_check                  ;     continue
.loop_skip_current:                               ; def Handler.NameMismatchException() @contextual:
    and     di, 00001111111111100000b             ;     $di = ($di >> 5) << 5
    add     di, 32                                ;     $di += 32
    mov     si, LoaderFileName                    ;     $ds, $si = BaseOfBooter, LoaderFileName
    jmp     .loop_seek_loader                     ;     break
.loop_loader_not_found:                           ; def Handler.LoaderNotFoundException():
    mov     dh, 2                                 ;
    call    print_idx                             ;     print_idx(2)
    jmp     $                                     ;     halt()
.loop_loader_found:                               ; def.Handler.LoaderFoundInterruption():
    mov     ax, SectorOccupiedByRoot              ;     $ax = SectorOccupiedByRoot
    and     di, 00001111111111100000b             ;     $di = ($di >> 5) << 5
    add     di, 00000000000000010110b             ;     $di += 26
    mov     cx, word [es:di]                      ;     $cx = sys.memory[$es:$di]
    push    cx

    add     cx, ax
    add     cx, OffsetSectorNo                    ;     $cx += SectorOccupiedByRoot + OffsetSectorNo    
; Variable Segment
word_idx_of_root_sec        dw SectorOccupiedByRoot
word_target_sector          dw 0
byte_is_odd                 db 0

LoaderFileName              db "PM      SYS"

MessageLength              equ 15

MessageBase:
MessageBootStart            db "Booting        " ; String index 0
MessageLoaderReady          db "Loader ready.  " ; String index 1
MessageLoaderMiss           db "Loader missing." ; String index 2

; Utility Functions Segment
print_idx:                                        ; def print_idx(mess_idx in $dh):
mov     ax, MessageLength                         ;     $ax = MessageLength
mul     dh                                        ;     $ax *= mess_idx
add     ax, MessageBase                           ;     $ax += MessageBase
mov     bp, ax                                    ;     $es, $bp = BaseOfBooter, $ax
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
mov     ax, BaseOfLoader - 0100h
mov     es, ax                                    ;     $es = BaseOfLoader - 0100h
pop     ax

mov     byte [byte_is_odd], 0                     ;     is_odd = False

mov     bx, 3
mul     bx                                        ;     _, $ax = sys.dualreg_unstack(ax * 3)
mov     bx, 2
div     bx                                        ;     $dx, $ax = $ax % 2, $ax / 2
cmp     dx, 0
jz      .is_even                                  ;     if $dx != 0:
mov     byte [byte_is_odd], 1                     ;         is_odd = True
.is_even:                                         ;
    mov     bx, FAT12_BytesPerSector              ;     $bx = FAT12_BytesPerSector
    div     bx                                    ;     $ax, $dx = $ax / $bx, $ax % $bx
    push    dx

    xor     bx, bx                                ;     $bx = 0
    add     ax, SectorBaseFAT1                    ;     $ax += SectorBaseFAT1
    mov     cl, 2
    call    read_sector                           ;     read_sector(sec_base=$ax, sec_num=2, target_seg=sys.memory[$es:$bx])

    pop     dx
    add     bx, dx                                ;     $bx += $dx

    mov     ax, [es:bx]                           ;     $ax = sys.memory[$es:$bx]
    cmp     byte [byte_is_odd], 1                 ;     if is_odd:
    jnz     .is_even_branch0
    shr     ax, 4                                 ;         $ax >>= 4

.is_even_branch0:
    and     ax, 0000111111111111b                 ;     $ax &= 0000111111111111b

pop     bx
pop     es

ret                                               ;     return $ax

times (510 - ($-$$))        db 0
dw      0xaa55
times (1474560 - ($-$$))    db 0
