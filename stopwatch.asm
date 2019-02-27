#include "msp430.h"                             ; #define controlled include file

                NAME    main                    ; module name

                PUBLIC  main                    ; make the main label vissible
                                                ; outside this module
                ORG     0FFFEh
                DC16    init                    ; set reset vector to 'init' label

                RSEG    CSTACK                  ; pre-declaration of segment
                RSEG    DATA16_N                       
;state led's green = start red = stop blue = set
LED_GREEN:      DB      0x80
LED_RED:        DB      0x10
LED_BLUE:       DB      0x40

;bit positions for digits
dig1:           DB      0x01
dig2:           DB      0x02
dig3:           DB      0x04
dig4:           DB      0x08
alloff:         DB      0x00
allon:          DB      0xFF

;state flags
STARTED_FLAG:   DB      0x04
STOPPED_FLAG:   DB      0x02
SET_FLAG:       DB      0x01

;array for displayed numbers - zero through nine
;zeros in segment positions = on, ones = off
numbers:        DC8     0xC0, 0xF9, 0xA4, 0xB0, 0x99, 0x92, 0x82, 0xF8, 0x80, 0x98
                RSEG    CODE                            ; place program in 'CODE' segment

init:           MOV     #SFE(CSTACK),   SP              ; set up stack

main:           NOP                                     ; main program
                MOV.W   #WDTPW+WDTHOLD, &WDTCTL         ; Stop watchdog timer
                CALL    #setupRegisters
                CALL    #setupIO
                CALL    #setupClock
                BIS.B   #(GIE),         SR              ; enable global interups
                
                
                JMP $                                   ; jump to current location '$'
                                        
setupRegisters:
                MOV     #0,             R10             ; used to track what digit set is on
                MOV.B   #0,             R11             ; index for number in dig4
                MOV.B   #0,             R12             ; index for number in dig3
                MOV.B   #0,             R13             ; index for number in dig2
                MOV.B   #0,             R14             ; index for number in dig1
                MOV.B   STOPPED_FLAG,   R8              ; state flag register
                MOV.B   #0,             R5              ; byte being moved into shift reg 
                RET


;sets up our gpio pins for input and output
setupIO:
                BIC     #LOCKLPM5,      PM5CTL0        ; turn on io pins  
                MOV.B   #0xDF,          &P1DIR         ; set up shift reg for output
                MOV.B   #0x00,          &P1OUT
                MOV.B   LED_RED,        &P1OUT         ; start with red led on
                
                ;set up buttons for input
                MOV.B   #0x00,          &P2DIR          
                MOV.B   #0x27,          &P2REN
                MOV.B   #0x27,          &P2OUT
                MOV.B   #0x27,          &P2IE      
                
                RET
        
setupClock:
                ;set clock and timer
                ;timer 0 
                BIS     #SELA,          &CSCTL4
                BIS     #TACLR,         &TA0CTL
                BIS     #(TASSEL_1 + MC_1), &TA0CTL
                MOV     #33000,         &TA0CCR0
                BIS     #CCIE,          &TA0CCTL0
                
                ;timer 1
                BIS     #TACLR,         &TA1CTL
                BIS     #(TASSEL_1 + MC_1), &TA1CTL
                MOV     #80,            &TA1CCR0
                BIS     #CCIE,          &TA1CCTL0


;waits a small amount of time - right now like <1ms
;change this to timer perhaps
wait:
                MOV     #50,            R7
wait_l:         DEC     R7
                TST     R7
                JNZ     wait_l
                RET
        
;shift_out is called by timer1. Its called once every few ms       
;shifts a byte 1 bit at a time into our shift register IC (HC595)
;then saves it in its storage register to be output       
shift_out:
                MOV     #8,             R4
bitloop:
                RLA.B   R5
                JNC     nc
c:              BIS.B   #0x01,          &P1OUT
                JMP     past_nc
nc:             BIC.B   #0x01,          &P1OUT
past_nc:
                BIS.B   #0x02,          &P1OUT         ;turn on/off sh_clk
                BIC.B   #0x02,          &P1OUT   
                DEC     R4
                TST     R4
                JNZ     bitloop
        

                RET
                
;shift_out_save is called once we shift the digit byte and
;number byte into the
;shift register - it will save its contents and output it
;through 12 pins in parallel once it is saved.                
shift_out_save:
st_cp:          BIS.B   #0x04,          &P1OUT         ;turn on/off st_clk to save data
                BIC.B   #0x04,          &P1OUT
                RET

;blink_dig is called when the user is setting the clock
;when we are on the corresponding digit - it blinks!
blink_dig:
                CMP      #1,            R10             ;check if in dig4
                JNZ      blink_dig3
                XOR.B    #0x08,         &dig4
blink_dig3:     CMP      #2,            R10
                JNZ      blink_dig2
                XOR.B    #0x04,         &dig3
blink_dig2:     CMP      #3,            R10
                JNZ      blink_dig1
                XOR.B    #0x02,         &dig2
blink_dig1:     CMP      #4,            R10
                JNZ      end_blink
                XOR.B    #0x01,         &dig1
end_blink:
                RET

;this is called each time the set button is pressed
;this way if the user switches between setting digits
;when the led is in mid blink we turn it back on
reset_dig_leds:
                MOV.B    #0x08,         &dig4
                MOV.B    #0x04,         &dig3
                MOV.B    #0x02,         &dig2
                MOV.B    #0x01,         &dig1
                RET
        
        
;Interupt Service Routine for button presses
;P2.0 = start button - start countdown timer for clock  - sets start flag
;P2.1 = stop button - stops countdown timer for clock   - sets stop flag
;P2.2 = set button - starts blink timer for display in digX - sets set flag
;                  - press again to change to next dig - when pressed 4 times - set stop flag
;P2.5 = up button  - increments registers holding numeric values in digX - must be
;                  - in set mode (set flag is 1) 

;as of 11.25.18 - most of these things are todo
button_ISR:
start_button:
                CMP.B    #0x01,         &P2IFG          ;check to see if p1.0 interupt flag enabled
                JNZ      stop_button                    ;if false - go to stop button label
                MOV.B    STARTED_FLAG, R8               ;if true - set flag state to start - 0x04
                MOV.B    LED_GREEN,     &P1OUT          ;turn on green led
                JMP      endISR
stop_button:
                CMP.B    #0x02,         &P2IFG          ;check to see if p1.1 interrupt flag enabled
                JNZ      set_button                     ;if false - go to set button label
                MOV.B    STOPPED_FLAG,  R8              ;otherwise - set flag state to stop - 0x02
                MOV.B    LED_RED,       &P1OUT          ;turn on red led
                JMP      endISR
set_button:
                CMP.B    #0x04,         &P2IFG          ;check to see if p1.2 interrupt flag enabled
                JNZ      up_button                      ;if false - go to up button label
                CMP.B    STARTED_FLAG,  R8              ;check to make sure we're not in start state
                JZ       endISR                         ;if we are exit ISR
                MOV.B    LED_BLUE,      &P1OUT          ;otherwise set state led
                MOV.B    SET_FLAG,      R8              ;set state flag
                CALL     #reset_dig_leds
                INC      R10                            ;Increment R10 - starts at 1, goes to 4, cooresponds to what dig we're on
                CMP      #5,            R10             ;if its 5 - then reset it to 0 - and change to stop state
                JGE      zero_dig      
                JMP      endISR
zero_dig:
                ;change to stop state - 0 out dig value - stop blink timer
                MOV      #0,            R10             
                BIC.B    #0xFF,         &P2IFG
                MOV.B    #0x02,         &P2IFG
                JMP      stop_button                                       
up_button:
                CMP.B    #0x20,         &P2IFG           ;check to see if p1.5 interrupt flag enabled
                JNZ      endISR
                CMP.B    SET_FLAG,      R8               ; make sure in set state to do up operations
                JNZ      endISR                          ; we will set from right to left
inc_d4:    
                CMP      #1,            R10              ; 1 = dig4
                JNZ      inc_d3
                INC      R11                             ; R11 holds index for number in dig4
                CMP      #10,           R11              ; if R11 is 10 we need to reset it to 0
                JGE      reset_d4
                JMP      endISR
reset_d4:
                MOV      #0,            R11
inc_d3:    
                CMP      #2,            R10              ; 2 = dig3
                JNZ      inc_d2
                INC      R12                             ; R12 holds index for number in dig3
                CMP      #10,           R12
                JGE      reset_d3
                JMP      endISR
reset_d3:
                MOV      #0,            R12
inc_d2:    
                CMP      #3,            R10              ; 3 = dig2
                JNZ      inc_d1
                INC      R13                             ; R13 = dig2
                CMP      #10,           R13
                JGE      reset_d2
                JMP      endISR
reset_d2:
                MOV      #0,            R13  
inc_d1:    
                CMP      #4,            R10              ; 4 = dig1
                JNZ      endISR
                INC      R14                             ; R14 = dig1
                CMP      #10,           R14
                JGE      reset_d1
                JMP      endISR
reset_d1:
                MOV      #0,            R14
       
endISR:
                MOV.B    #0x00,         &P2IFG
       
                RETI

;subtracts 1 from whatever is left in our timer
;since we have multiple indexes corresponding to array values - we do it this way
;if the index is zero - it maps to the value 0 in the array - and so on
;when all index's are zero we set off an alarm which pulses at
;the timers rate
timer_ISR:      
check_set:      CMP.B   SET_FLAG,       R8               ;if in set state - blink digit in display
                JNZ     check_start
                CALL    #blink_dig
check_start:    CMP.B   STARTED_FLAG,   R8               ;check to make sure in started state to run code
                JNZ     end_isr
d4:             TST     R11                              ;testing dig4 to dig1 to see if any numbers not 0              
                JZ      d3
                DEC     R11                              ; if its not 0 then decrement the value
                JMP     end_isr                          
d3:             TST     R12              
                JZ      d2
                DEC     R12
                MOV     #9,             R11              ; if we take away 1 in tens - add 9 to ones
                JMP     end_isr
d2:             TST     R13
                JZ      d1
                DEC     R13
                MOV     #9,             R12              ; take 1 from hundreds - move 9 to tens and ones
                MOV     #9,             R11
                JMP     end_isr
d1:             TST                     R14
                JZ      alarm                            ; everything is zero if we get here
                DEC     R14
                MOV     #9,             R11              ; take 1 from thousands - move 9 to other spots
                MOV     #9,             R12
                MOV     #9,             R13
                JMP     end_isr
alarm:  
                XOR.B   #0x08,          &P1OUT            ; toggle buzzer
end_isr:
                BIC     #TAIFG,         &TA0CTL           ; clear any interupt flags in timer
                RETI
        
        
;gets called every ms or so - just outputs our current time state
;shifts out a digit byte then a number byte - then saves state
;we have to do one digit at a time in sequence so we can show 4 different numbers
;basically it just flashes through the numbers in sequence really fast to give the
;illusion that its one constant output.     
display_timer_ISR:
                MOV.B   dig4,           R5                               
                CALL    #shift_out
                MOV.B   numbers(R11),   R5                      
                CALL    #shift_out
                CALL    #shift_out_save                          
        
                MOV.B   dig3,           R5                      
                CALL    #shift_out
                MOV.B   numbers(R12),   R5              
                CALL    #shift_out
                CALL    #shift_out_save                            
        
                MOV.B   dig2,           R5                      
                CALL    #shift_out
                MOV.B   numbers(R13),   R5              
                CALL    #shift_out
                CALL    #shift_out_save
                ;CALL    #wait       
        
                MOV.B   dig1,           R5                      
                CALL    #shift_out
                MOV.B   numbers(R14),   R5              
                CALL    #shift_out
                CALL    #shift_out_save
                ;CALL    #wait       
                BIC     #TAIFG, &TA1CTL
        RETI
       
       
       ;define ISRs for timer and io ports
       Common     INTVEC
       ORG        TIMER0_A0_VECTOR
       DW         timer_ISR 
       
       Common     INTVEC
       ORG        TIMER1_A0_VECTOR
       DW         display_timer_ISR
       
       Common     INTVEC
       ORG        PORT2_VECTOR
       DW         button_ISR
        
        
       END
