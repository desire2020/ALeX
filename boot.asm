org     07c00h

%include "memalloc.lib"

jmp     short __start
%include "FAT12.lib"


; Code Segment
__start:
mov     ax, cs
mov     ds, ax
mov     es, ax
mov     ss, ax
mov     sp, BaseOfStack

mov     ax, 0600h
mov     bx, 0700h
mov     cx, 0
mov     dx, 0184fh
int     10h                                       ; sys.graphics.clrscr()

mov     dh, 0                                     ;
call    print_idx                                 ; print_idx(0)
xor     ah, ah
xor     dl, dl
int     13h                                       ; sys.floppy.call(sys.floppy.reset)

mov     word [wSectorNo], SectorIdxOfRoot
                                                  ; idx_of_root = SectorIdxOfRoot
.loop_start:                                      ; while True:
    cmp     word [wCounterRootSec], 0             ;     if idx_of_root == 0:
    jz      .loop_loader_not_found                ;         throw LoaderNotFoundException()
    dec     word [wCounterRootSec]                ;     idx_of_root -= 1
    mov     ax, BaseOfLoader                      ;     $es = BaseOfLoader
    mov     es, ax                                ;     base = BaseOfLoader
    mov     bx, OffsetOfLoader                    ;     offset = OffsetOfLoader
    mov     ax, [wSectorNo]                       ;     target_start = target_sector
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
    jz      .loop_loader_found                    ;                     throw LoaderFoundSignal()
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
    mov     si, LoaderFileName                    ;     $ds, $si = BaseOfBooter, LoaderFileName
    jmp     .loop_seek_loader                     ;     break
.loop_loader_not_found:                           ; def Handler.LoaderNotFoundException():
    mov     dh, 2                                 ;
    call    print_idx                             ;     print_idx(2)
    jmp     $                                     ;     halt()
.loop_loader_found:                               ; def.Handler.LoaderFoundSignal():
    mov     ax, RootDirSectors                    ;     
    and     di, 0FFE0h                            ;     $di = ($di >> 5) << 5
    add     di, 01Ah                              ;     $di += 26
    mov     cx, word [es:di]                      ;     $cx = sys.memory[$es:$di]
    push    cx                                    ;     sys.stack.write($cx)

    add     cx, ax
    add     cx, OffsetSectorNo                    ;     $cx += RootDirSectors + OffsetSectorNo    
    mov     ax, BaseOfLoader                      ;     
    mov     es, ax                                ;     $es = BaseOfLoader
    mov     bx, OffsetOfLoader                    ;     $bx = OffsetOfLoader
    mov     ax, cx                                ;     $ax = $cx

.loop_loop_read_loader:                           ;     while True:
    push    ax
    push    bx
    mov     ah, 0Eh                               ;         write(sys.graphics, '.')
    mov     al, '.'
    mov     bl, 0Fh
    int     10h
    pop     bx
    pop     ax      
    


    mov     cl, 1
    call    read_sector                           ;         read_sector(sec_base = $ax, sec_num = 1, target_seg=[BaseOfLoader: OffsetOfLoader])

    pop     ax                                    ;         sys.stack.read_and_pop($ax)
    call    get_FAT_entry                         ;         $ax = get_FAT_entry(sector_no = $ax)

    
    cmp     ax, 0FFFh                             ;         if $ax == 0FFFh:
    jz      .loop_read_loader_done                ;             break
    push    ax                                    ;         sys.stack.write($ax)
    add     ax, RootDirSectors                    ;         $ax += RootDirSectors
    add     ax, OffsetSectorNo                    ;         $ax += OffsetSectorNo
    add     bx, [FAT12_BytesPerSector]            ;         $bx = OffsetOfLoader + FAT12_BytesPerSector
    jmp     .loop_loop_read_loader

.loop_read_loader_done:
    mov     dh, 1                                 
    call    print_idx                             ;     print_idx(1)

    jmp     BaseOfLoader: OffsetOfLoader          ;     sys.unsafe.goto(BaseOfLoader:OffsetOfLoader) 
    mov     dh, 3                                 
    call    print_idx                             ;     print_idx(3)
    jmp     $
; Variable Segment
wCounterRootSec             dw RootDirSectors
wSectorNo                   dw 0
bIsOdd                      db 0

LoaderFileName              db "PM-X86  SYS", 0

MessageLength              equ 15

MessageBase:
MessageBootStart            db "Booting        " ; String index 0
MessageLoaderReady          db "Loader ready.  " ; String index 1
MessageLoaderMiss           db "Loader missing." ; String index 2
MessageDebug                db "Real Mode back." ; String index 3

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
mov     ax, BaseOfLoader
sub     ax, 0100h
mov     es, ax                                    ;     $es = BaseOfLoader - 0100h
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

times (510 - ($-$$))        db 0
dw      0xaa55