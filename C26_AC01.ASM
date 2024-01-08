;-----------------------------------------------------------;
; DSK_SPEC.ASM                                              ;
; (C) 1992-93                                               ;
; Texas Instruments Inc.                                    ;
; By: Keith Larson                                          ;
;     TMS320Cxx DSP Applications                            ;
;                                                           ;
; 2024                                                      ;
; mx68k                                                     ;                                                        ;                                                           ;
; A spectrum analyzer using the DSK                         ;
; Use an Oscilliscope on the analog output to view the      ;
; spectrum of the signal at the analog input!               ;
;                                                           ;
; To use this code, start the debugger DSKD.  Then load     ;
; DSK_SPEC.DSK (LD command), then hit F5 (run key).         ;
; You may need to adjust your oscilliscope trigger to get   ;
; a stable waveform.  Use AUTO triggering with DC coupling  ;
; to more reliably catch the synch pulse at the beginning   ;
; of each frame!                                            ;
;                                                           ;
; NOTE:                                                     ;
; Check the HOSTSPEC program in the DSKL directory for a    ;
; host based analyzer that does not need an oscilliscope.   ;
; This program is run from within DSKL, NOT DSKD!  Be sure  ;
; to read the document and .ASM beginning code statements   ;
;-----------------------------------------------------------;
;  Use WTRFALL .set  YES   ;to turn on the time 'Z' axis!   ;
;-----------------------------------------------------------;
YES     .set    1               ;
NO      .set    0               ;
FFT256  .set    YES             ; NOTE: WTRFALL can be set via DSKA options
FFT128  .set    NO              ;
WTRFALL .set    NO              ; DSKA DSKSPEC asm"WTRFALL .set 1"
 .if  FFT256                    ;
FFT_S           .set    256     ;
FFT_S-1         .set    255     ;
FFT_S/2         .set    128     ;
(FFT_S/2)-1     .set    127     ;
 .endif                         ;
 .if  FFT128                    ;
FFT_S           .set    128     ;
FFT_S-1         .set    127     ;
FFT_S/2         .set    64      ;
(FFT_S/2)-1     .set    63      ;
 .endif                         ;
;-----------------------------------------------------------;
;---------------TLC32040 registers--------------------------;
;-----------------------------------------------------------;
AIC_1           .set    00C18h  ;TA =RA = 6  00_00110_00_00110_00 = 00C18h
AIC_2           .set    00205h  ;TA'=RA'= 1  0_000001_0_000001_01 = 00205h
AIC_3           .set    0264eh  ;TB =RB =13h 0_010011_0_010011_10 = 0264ch 44khz
AIC_CMD         .set    00003h  ;   COMMAND  00000000_000000_11 = 00083h
;-----------------------------------------------------------;
;-----------------------------------------------------------;
;---------------TLC320AC01 registers--------------------------;
;-----------------------------------------------------------;
PR1 		.set 	00104h ;A register                      00000100000100
PR2 		.set 	00219h ;B register                      00001000011001
PR3 		.set 	00300h ;A prime register                00001100000000
PR4 		.set 	00405h ;amplifier gain register         00010000000101
PR5 		.set 	00501h ;analog configuration register   00010100000001
PR6 		.set 	00600h ;digital configuration register  00011000000000
PR7 		.set 	00730h ;frame synch delay register      00011100110000
PR8 		.set 	00802h ;frame synch number register     00100000000010
;-----------------------------------------------------------;
 .if WTRFALL                    ;
d_loops         .set    010h    ; synch pulse delay loop
 .else                          ;
d_loops         .set    03Fh    ; synch pulse delay loop
 .endif                         ;
TEMPX           .set    060h    ; STATUS storage
STAT1           .set    061h    ; STATUS storage
ACCU_lo         .set    062h    ;
ACCU_hi         .set    063h    ;
TEMP            .set    064h    ; location of TEMPorary storage
WIDTH           .set    065h    ;
HEIGHT          .set    066h    ;
;----------------------------------------------------------------
;    SECONDARY VECTOR TABLE LOACTED IN B0 PROGRAM RAM
;----------------------------------------------------------------
        .include  "mmregs.asm"  ;     > USERCODE SHOULD NOT OVERWRITE DSKD  <
        .ps     0fa00h          ;     > VECTORS.  ON LOAD, INT2 IS RESTORED <
        B       start           ;RS   > BY DSKD, BUT TRAP IS NOT            <
        B       start           ;INT0
        B       start           ;INT1
        B       start           ;INT2  > DSKD LOAD IGNORES INT2 VECTOR
        B       start           ;TINT
        B       RINT            ;RINT  Branch to receive interrupt routine
        eint                    ;XINT  XINT is only for timing, so just return
        ret                     ;
      ; Begin TRAP/DSKD Kernal  ;DSKD load does not restore this code!
;----------------------------------------------------------------
;    APPLICATION CODE IS LOCATED ABOVE DSKD KERNAL
;----------------------------------------------------------------
        .ps     0FB00h          ;
        .entry                  ;
start:  ldpk    0               ; All direct addressing is to MMRs and B2
        fort    0               ; Serial port : 16 bit
        rtxm                    ;             : ext. FSX
        sfsm                    ;             ; burst mode
        lack    080h            ; AIC reset by pulsing /BR (Global Data)
        sach    DXR             ; send 0 to DXR (AIC)
        sacl    GREG            ; 256 * 100 nS /BR pulse
        lrlk    AR0,0FFFFh      ;
        rptk    255             ; read junk from address 0xFFFF
        lac     *,0,AR0         ;
        conf    1               ; B1,B3 as DRAM if direct bootload
        sovm                    ; catch accumulator overflows
;--------------------------------
AIC_RS  lack    024h            ; Turn on XINT
        sacl    IMR             ;
        idle                    ;
;		lalk    AIC_1           ; Load each AIC configuration word
        lalk    PR1           ; Load each AIC configuration word
        call    AIC_2nd         ; and load it into the AIC
;        lalk    AIC_2           ;		
        lalk    PR2           ;
        call    AIC_2nd         ;
;        lalk    AIC_3           ;		
        lalk    PR8           ;
        call    AIC_2nd         ;
;        lalk    AIC_CMD         ;		
        lalk    PR7         ;
        call    AIC_2nd         ;
;----------------------------------------------------------------
        lark    AR7,0           ; Buffer initialy filled
        ssxm                    ;
        lack    014h            ; AIC RINT
        sacl    IMR             ; where INT0 indicates EOC (End Of Conv)
        ;---------------------------------------------------------------
        lark    AR7,0           ; Buffer initialy filled
FFT:    lrlk    AR0,FFT_S/2     ;
        larp    AR0             ; start FFT with AR0=FFTSize
new_stg lrlk    AR1,_D_base     ; AR1 is the TOP BFLY address
        lrlk    AR2,_D_base     ; AR2 is the BOT BFLY address
        lrlk    AR3,_T_base+1   ; AR3 is the TWiddle pointer
        lrlk    AR4,FFT_S/2     ; AR4 counts DFT blocks
        b       n_DFT2,*,AR1    ;
DFT:    mar     *BR0+,AR5       ; complete circular buffer for TW's
        lark    AR5,1           ; set up DFT loop with *BR0+/BANZ
        mar     *BR0+,AR1       ; using 1 cuts *BR0+ loop in half!
        ;----------------------------------------
        ; AR1=Top AR2=Bottom AR3=Twiddle
        ;----------------------------------------
BFLY:   lac     *,14,AR2        ;(imag1+imag2)/4
        add     *,14,AR1        ;
        sach    *+,1,AR2        ;store TOP imag
        sub     *,15            ;(imag1-imag2)/2
        sach    *+,1,AR1        ;store BOT imag
        lac     *,14,AR2        ;(real1+real2)/4
        add     *,14,AR1        ;
        sach    *+,1,AR2        ;store TOP real
        sub     *,15            ;(real1-real2)/2
        sach    *,1,AR5         ;store BOT real
        banz    OK,*BR0+,AR3    ;If at DFT end quit early
        ;------------------------
        mar     *+,AR2          ;clean up TW base (xxx0000+1)
        mar     *+              ;modify BOTom DATA pointer
        mar     *0+             ;
        mar     *0+,AR1         ;
n_DFT2: mar     *0+             ;modify the TOP pointer
        mar     *0+,AR4         ;
        banz    DFT,*0-,AR3     ;dec DFT block count AR4 by OFFset
        larp    AR0             ;
        mar     *BR0+           ;
        banz    new_stg,*       ;if OFFset was 1, now cleared
        b       endFFT          ;
         ;-------------------------
OK      lt      *-,AR2          ;TREG=TWR     *NOTE* Twiddles are Q15
        mpy     *-              ;PREG=REAL*TWR
        ltp     *+,AR3          ;TREG=IMAG     ACCU=REAL*TWR
        mpy     *               ;PREG=IMAG*TWI                AR2=R AR3=I
        lts     *+,AR2          ;TREG=TWI      ACCU=REAL*TWR-IMAG*TWI
        mpy     *               ;PREG=REAL*TWI
        sach    *-,1,AR2  ;<<<<<;
        ltp     *,AR3           ;TREG=IMAG     ACCU=REAL*TWI
        mpy     *BR0+,AR2       ;PREG=IMAG*TWR
        apac                    ;              ACCU=IMAG*TWR+REAL*TWI
        sach    *+,1,AR2  ;<<<<<;
        b       BFLY,*+,AR1     ;
        ;------------------------------------------------------------
endFFT: larp    AR2             ;Transform REAL & IMAG to log magnitude
        lrlk    AR2,_D_base     ;AR3=FFT data pointer
        lrlk    AR3,FFT_S-1     ;AR5=FFT loop counter
more_MAG sqra    *+             ;PREG=IMAG^2
        ltp     *               ;TREG=REAL    ACCU=IMAG^2
        mpy     *,AR1           ;PREG=REAL^2
        apac                    ;ACCU=REAL^2+IMAG^2
        lark    AR1,31          ;NORMalize the accumulator
        rptk    30              ;use for other types of conversion
        norm    *-              ;
        bnz     sig_NZ,*,AR2    ;if zero must return 0
        lark    AR1,0           ;
sig_NZ  sach    *,2,AR2   ;<<<<<;clear explicit 1.0 from mantissa
        zals    *               ;load into accumulator and
        andk    0FF80h          ;; clear LSB's for AIC
        sar     AR1,*           ;append the exponent (AR5)
        addh    *               ;
        xork    020h,15         ;change to 2's compliment
        rptk    3               ;jam result to top of ACCU
        sfl                     ;
        sach    *+,7,AR3        ;
        banz    more_MAG,*-,AR2 ;keep going until all done
        ;--------------------------------------------------------
BITREV: lrlk    AR0,FFT_S       ;Now perform Output bit reversal
        lrlk    AR1,_D_base     ;by moving the magnitude, which
        lrlk    AR2,_D_base+1   ;is in the REAL slots, into the
        lrlk    AR3,FFT_S-1     ;IMAG slots of the FFT data array
more_BR lac     *+              ;load the magnitude
        mar     *+,AR1          ;
        sacl    *BR0+,0,AR3     ;move it to an open IMAG slot
        banz    more_BR,*-,AR2  ;more data to move?
        ;--------------------------------------------------------
MOVE_IO larp    AR7             ;wait until buffer is full
        banz    MOVE_IO,*,AR2   ;(AR7 is decremented by ISR)
        lrlk    AR3,_D_base     ;AR3=FFT data pointer
        lrlk    AR4,_B_base     ;AR4=BUFF data pointer
        lrlk    AR5,(FFT_S/2)-1 ;AR5=FFT loop counter
        lrlk    AR6,_B_base     ;AR6=ISR BUFF data pointer
        lalk    08000h          ;send synch when BUFF is full
        sacl    DXR             ;
 .if WTRFALL                    ;
        lac     WIDTH           ;Adjust X&Z-axis for Waterfall display
        addk    010h            ;Height and Width adjust 0-15 (x8)
        andk    0FFh            ;
        sacl    WIDTH           ;
        sacl    HEIGHT,6        ;
 .endif                         ;
        lark    AR2,d_loops     ;
delay:                          ;
 .if WTRFALL                    ;
        rpt     WIDTH           ;2,18,34,50,66... cycle delay
        nop                     ;
 .endif                         ;
        rptk    060h            ;
        nop                     ;
        banz    delay,*-        ;
        lrlk    AR2,_T_base+1   ;AR2=WIN data pointer
        lrlk    AR7,FFT_S-1     ;AR7=ISR BUFF loop counter
        ;-------------------------
        lrlk    AR0,FFT_S/2     ; Use twiddle table for raised
more_IO lalk    04000h,1        ; cosine window
        add     *BR0+,0,AR4     ;
        sfr                     ;
        sacl    TEMP            ;
        lt      TEMP            ;TREG=WIN
        mpy     *,AR3           ;PREG=IN*WIN
        zals    *,AR4           ;ACCU=magnitude (put in Buffer)
        sacl    *+,0,AR3        ;
        sach    *+,0,AR3  ;<<<<<;IMAG=0
        pac                     ;
        sach    *+,1,AR5        ;REAL=IN (windowed buffer)
        eint                    ;1st BUFF posn clr so enable INT's
        banz    more_IO,*-,AR2  ;
        lrlk    AR5,(FFT_S/2)-1 ;AR5=FFT loop counter
more_IO2 lalk    04000h,1       ; cosine window
        add     *BR0-,0,AR4     ;
        sfr                     ;
        sacl    TEMP            ;
        lt      TEMP            ;TREG=IN
        mpy     *,AR3           ;PREG=IN*WIN
        zals    *,AR4           ;ACCU=magnitude (put in Buffer)
        sacl    *+,0,AR3        ;
        sach    *+,0,AR3  ;<<<<<;IMAG=0
        pac                     ;
        sach    *+,1,AR5        ;REAL=IN (windowed buffer)
        banz    more_IO2,*-,AR2 ;
        b       FFT             ;
;-----------------------------------------------------------------
RINT:   sst1    STAT1           ;Recover ARP from ARB by LST1 last
        larp    AR7             ;AR6 = current buffer position
        banz    more_buf,*-,AR6 ;if buffer is full RET w/o EINT
        lark    AR7,0           ;
        lst1    STAT1           ;
        ret                     ;
more_buf                        ;
        sacl    ACCU_lo         ;
        sach    ACCU_hi         ;
        zalh    *               ; ACCU = FREQ + OFFSET + HEIGHT
        adlk    06000h,15       ; using ACCU_hi for OVFLW protection
 .if WTRFALL                    ;
        addh    HEIGHT          ; add HEIGHT
 .endif                         ;
        sach    *               ;
        lac     *               ;
        andk    0FFFCh          ;clear LSB's
        sacl    DXR             ;
        ;------------------------
        lac     DRR             ;
        bit     TEMPX,15        ;Inverting every other input aliases the
        bbz     NO_NVRT         ;frequency domain, swapping DC and Nyquist!
        neg                     ;
NO_NVRT                         ;
        sacl    *+              ;<<< store DRR, and point to next
        lac     TEMPX           ;
        xork    1               ;
        sacl    TEMPX           ;
        zalh    ACCU_hi         ;
        adds    ACCU_lo         ;
        lst1    STAT1           ;
        eint                    ;
        ret                     ;
******************************************************************
AIC_2nd adlk    6,15            ;set ACCU_hi = 3 for secondary XMIT
        idle                    ;Wait for a XINT
        sach    DXR             ;
        idle                    ;ACCU_hi requests 2nd XMIT
        sacl    DXR             ;
        idle                    ;ACCU_lo sets up registers
        sacl    DXR,2           ;close command with LSB = 00
        idle                    ;
        eint                    ;
        ret                     ;
;====================================================================
        .listoff                ;
        .ds     00400h          ;NOTE: Twiddles are relocated to
        .include "dsk_twid.asm" ;      0400h (B2) using CONF 1
        .liston

