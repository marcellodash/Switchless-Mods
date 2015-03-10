#include <p12f635.inc>

; -----------------------------------------------------------------------
;   NES "In-game reset" (IGR) controller
;
;   Copyright (C) 2015 by Peter Bartmann <peter.bartmann@gmx.de>
;
; -----------------------------------------------------------------------
;
;   This program is designed to run on a PIC 16F630 microcontroller connected
;   to the controller port and NES main board. It allows an NES to be reset
;   via a standard controller.
;
;   pin configuration: (controller port pin) [Mainboard pin/pad]
;
;                                         ,----_-----.
;                    +5V (7) [CIC Pin 16] |1        8| GND (1) [CIC Pin 15]
;   Reset - out (-) [CIC Pin 7/CPU Pin 3] |2  A5 A0 7| serial data in (4) [U7 74HC368 Pin 2]
;                 Resettype -  in (*) [*] |3  A4 A1 6| latch in (3) [CPU Pin 39]
;                       n.c. in (**) [**] |4  A3 A2 5| clk in (2) [CPU Pin 36]
;                                         `----------'
;
;   As the internal oscillator is used, you should connect a capacitor of about 100nF between
;   Pin 1 (Vdd/+5V) and Pin 8 (Vss/GND) as close as possible to the PIC. This esures best
;   operation.
;
;   * Resettype:
;     - Pin set tide to Vcc = low-active reset (e.g. Famicom)
;     - Pin set tide to GND = high-active reset (e.g. US-NES, consoles with CIC)
;
;
;   controller pin numbering
;   ========================
;
;        _______________
;       |               \     (1) - GND          (5) - not connected
;       | (5) (6) (7)    \    (2) - clk          (6) - not connected
;       | (4) (3) (2) (1) |   (3) - latch        (7) - Power, +5V 
;       |_________________|   (4) - serial data
;
;   key mapping: Start + Select +                            (stream data)
;   =============================
;   A + B       Reset                                           0x0f
;   (nothing)   Pressed for ~2s -> perform Longreset (3s)       0xcf
;
; -----------------------------------------------------------------------

; -----------------------------------------------------------------------
; Configuration bits: adapt to your setup and needs

    __CONFIG _INTRC_OSC_NOCLKOUT & _IESO_OFF & _WDT_OFF & _PWRTE_ON & _MCLRE_OFF & _CP_OFF & _CPD_OFF & _BOD_OFF

Debug   set 0 ; 0 = debug off, 1= debug on

; -----------------------------------------------------------------------
; macros and definitions

M_movff macro   fromReg, toReg  ; move filereg to filereg
        movfw   fromReg
        movwf   toReg
        endm

M_movpf macro   fromPORT, toReg ; move PORTx to filereg
        movfw   fromPORT
        andlw   0x3f
        movwf   toReg
        endm

M_movlf macro   literal, toReg  ; move literal to filereg
        movlw   literal
        movwf   toReg
        endm

M_beff  macro   compReg1, compReg2, branch  ; branch if two fileregs are equal
        movfw   compReg1
        xorwf   compReg2, w
        btfsc   STATUS, Z
        goto    branch
        endm

M_bepf  macro   compPORT, compReg, branch   ; brach if PORTx equals compReg (ignoring bit 6 and 7)
        movfw   compPORT
        xorwf   compReg, w
        andlw   0x3f
        btfsc   STATUS, Z
        goto    branch
        endm

M_belf  macro   literal, compReg, branch  ; branch if a literal is stored in filereg
        movlw   literal
        xorwf   compReg, w
        btfsc   STATUS, Z
        goto    branch
        endm

M_celf  macro   literal, compReg, call_func  ; call if a literal is stored in filereg
        movlw   literal
        xorwf   compReg, w
        btfsc   STATUS, Z
        call    call_func
        endm

M_delay_x05ms   macro   literal ; delay about literal x 05ms
                movlw   literal
                movwf   reg_repetition_cnt
                call    delay_x05ms
                endm

; -----------------------------------------------------------------------

CTRL_DATA   EQU 0
CTRL_LATCH  EQU 1
CTRL_CLK    EQU 2
N_C         EQU 3
RESET_IN    EQU 4
RESET_OUT   EQU 5

reg_ctrl_data       EQU 0x41
reg_overflow_cnt    EQU 0x42
reg_repetition_cnt  EQU 0x43
reg_current_mode    EQU 0x50
reg_previous_mode   EQU 0x51
reg_reset_type      EQU 0x60
reg_ctrl_reset      EQU 0x61

bit_reset_type          EQU RESET_OUT
code_reset_low_active   EQU (0<<bit_reset_type)  ; 0x00
code_reset_high_active  EQU (1<<bit_reset_type)  ; 0x20

bit_ctrl_reset_perform_long EQU 5
bit_ctrl_reset_flag         EQU 7

delay_05ms_t0_overflows EQU 0x0a    ; prescaler T0 set to 1:4 @ 8MHz
repetitions_045ms       EQU 0x09
repetitions_200ms       EQU 0x28
repetitions_300ms       EQU 0x3c
repetitions_1000ms      EQU 0xc8

; -----------------------------------------------------------------------
; buttons

BUTTON_A    EQU 7
BUTTON_B    EQU 6
BUTTON_Sl   EQU 5
BUTTON_St   EQU 4
BUTTON_Up   EQU 3
BUTTON_Dw   EQU 2
BUTTON_Le   EQU 1
BUTTON_Ri   EQU 0

; -----------------------------------------------------------------------

; code memory
 org    0x0000
    clrf    STATUS      ; 00h Page 0, Bank 0
    nop                 ; 01h
    nop                 ; 02h
    goto    start       ; 03h begin program / Initializing

 org    0x0004  ; jump here on interrupt with GIE set (should not appear)
    return      ; return with GIE unset

 org    0x0005
idle
    M_movlf 0xff, reg_ctrl_data
    btfsc   GPIO, CTRL_LATCH
    goto    read_Button_A       ; go go go
    bcf     INTCON, RAIF

idle_loop
    btfsc	INTCON, RAIF    ; data latch changed?
    goto    read_Button_A   ; yes
    goto    idle_loop       ; no


read_Button_A
    nop
    nop
    nop
    nop
    btfss   GPIO, CTRL_DATA
    bcf     reg_ctrl_data, BUTTON_A
    bcf     INTCON, INTF

wait_read_Button_B
    btfss   INTCON, INTF    ; wait for rising edge on clk
    goto    wait_read_Button_B
read_Button_B
    M_movlf 0x38, INTCON    ; clear INTF and RAIF (from now on, no IOC at the data latch shall appear)
    btfss   GPIO, CTRL_DATA
    bcf     reg_ctrl_data, BUTTON_B

wait_read_Button_Sl
    btfss   INTCON, INTF    ; wait for rising edge on clk
    goto    wait_read_Button_Sl
read_Button_Sl
    bcf     INTCON, INTF
    nop
    btfss   GPIO, CTRL_DATA
    bcf     reg_ctrl_data, BUTTON_Sl

wait_read_Button_St
    btfss   INTCON, INTF    ; wait for rising edge on clk
    goto    wait_read_Button_St
read_Button_St
    bcf     INTCON, INTF
    nop
    btfss   GPIO, CTRL_DATA
    bcf     reg_ctrl_data, BUTTON_St

wait_read_Button_Up
    btfss   INTCON, INTF    ; wait for rising edge on clk
    goto    wait_read_Button_Up
read_Button_Up
    bcf     INTCON, INTF
    nop
    btfss   GPIO, CTRL_DATA
    bcf     reg_ctrl_data, BUTTON_Up

wait_read_Button_Dw
    btfss   INTCON, INTF    ; wait for rising edge on clk
    goto    wait_read_Button_Dw
read_Button_Dw
    bcf     INTCON, INTF
    nop
    btfss   GPIO, CTRL_DATA
    bcf     reg_ctrl_data, BUTTON_Dw
    bcf     INTCON, INTF

wait_read_Button_Le
    btfss   INTCON, INTF    ; wait for rising edge on clk
    goto    wait_read_Button_Le
read_Button_Le
    bcf     INTCON, INTF
    nop
    btfss   GPIO, CTRL_DATA
    bcf     reg_ctrl_data, BUTTON_Le

wait_read_Button_Ri
    btfss   INTCON, INTF    ; wait for rising edge on clk
    goto    wait_read_Button_Ri
read_Button_Ri
    bcf     INTCON, INTF
    nop
    btfss   GPIO, CTRL_DATA
    bcf     reg_ctrl_data, BUTTON_Ri

wait_read_Button_None
    btfss   INTCON, INTF    ; wait for rising edge on clk
    goto    wait_read_Button_None

    btfsc   INTCON, RAIF
    goto    idle            ; another IOC on data latch appeared -> invalid read
	

checkkeys
    M_belf  0x0f, reg_ctrl_data, ctrl_reset                 ; Start+Select+A+B
    btfsc   reg_ctrl_reset, bit_ctrl_reset_flag             ; Start+Select+A+B previously detected?
    goto    doreset                                         ; if yes, perform a reset
	goto	idle

ctrl_reset
    btfss           reg_ctrl_reset, bit_ctrl_reset_flag
    goto            first_ctrl_reset                            ; first loop: set ctrl_reset_flag
    btfsc           reg_ctrl_reset, bit_ctrl_reset_perform_long
    goto            dolongreset
    M_delay_x05ms   repetitions_045ms
    incf            reg_ctrl_reset, 1
    goto            idle

first_ctrl_reset
    clrf    reg_ctrl_reset
    bsf     reg_ctrl_reset, bit_ctrl_reset_flag
    M_delay_x05ms   repetitions_045ms
    goto    idle

doreset
    banksel         TRISIO                   ; Bank 1
    bcf             TRISIO, RESET_OUT
    banksel         GPIO                   ; Bank 0
    M_movff         reg_reset_type, GPIO
    M_delay_x05ms   repetitions_300ms
    goto            release_reset

dolongreset
    banksel         TRISIO                   ; Bank 1
    bcf             TRISIO, RESET_OUT
    banksel         GPIO                   ; Bank 0
    M_movff         reg_reset_type, GPIO
    M_delay_x05ms   repetitions_1000ms
    M_delay_x05ms   repetitions_1000ms
    M_delay_x05ms   repetitions_1000ms

release_reset
    movfw   reg_reset_type
    xorlw   (1<<RESET_OUT)                      ; invert to release
    movwf   GPIO
    banksel TRISIO                               ; Bank 1
    bsf     TRISIO, RESET_OUT
    banksel GPIO                               ; Bank 0
    clrf    reg_ctrl_reset
    goto    idle


; --------delay calls--------
delay_05ms
    banksel TRISIO
    M_movlf 0xc1, OPTION_REG    ; make sure prescale assigned to T0 and set to 1:4
    banksel GPIO
    M_movlf delay_05ms_t0_overflows, reg_overflow_cnt
    clrf    TMR0    ; start timer

delay_05ms_loop_pre
    bcf     INTCON, T0IF

delay_05ms_loop
    btfss   INTCON, T0IF
    goto    delay_05ms_loop
    decfsz  reg_overflow_cnt, 1
    goto    delay_05ms_loop_pre
    return

delay_x05ms
    call    delay_05ms
    decfsz  reg_repetition_cnt, 1
    goto    delay_x05ms
    return

; --------initialization--------

start
    clrf    GPIO
    M_movlf 0x07, CMCON0        ; GPIO2..0 are digital I/O (not connected to comparator)
    M_movlf 0x38, INTCON        ; enable T0IE, RAIE and INTE to react on data latch and clock
    banksel TRISIO
    M_movlf 0x70, OSCCON        ; use 8MHz internal clock (internal clock set on config)
    M_movlf 0x3f, TRISIO        ; in in in in in in
    clrf    WPUDA               ; no pullups
    M_movlf 0x02, IOCA          ; IOC on DATA_LATCH
    M_movlf 0xc1, OPTION_REG    ; global pullup disable, use rising data clock edge for interrupt, prescaler T0 1:4
    banksel GPIO

detect_reset_type
    clrf    reg_reset_type
    movlw   code_reset_high_active
    btfss   GPIO, RESET_IN         ; jump next instruction for low-active reset
    movwf   reg_reset_type

init_end
    clrf    reg_ctrl_reset  ; clear this reg here just in case
    goto    idle

; -----------------------------------------------------------------------
theend
    END
; ------------------------------------------------------------------------