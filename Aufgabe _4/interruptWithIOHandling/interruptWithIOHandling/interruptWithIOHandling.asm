/*
 * Aufgabe4.asm
 *
 * Author: Heiko Pantermehl, Sheraz Azad, Sven Marquardt
 */ 
.include "m644PAdef.inc"	; device: ATmega 644PA
; ----- Am Beginn des Codespeichers liegt die Vektortabelle -----
;		Hier nur Sprungtabelle anlegen. Mindestens f�r den 
;		Reset-Interrupt (An Adresse 0):
	.org	0									; Am Anfang des Code-Speicher 
	jmp Main									; Sprung bei reset
	.org $0008									; External Pins wurden angesprochen hei�t PINA(7..0)
	jmp PCINT0_isr
	.org OC1Aaddr
	jmp OCRA1A_isr
	
; ***** Hier werden die "Variablen" definiert
	.dseg										; dies sind Daten
T1count:		.byte 1							; Z�hler f�r Wartefunktion mit Timer1
Nachtmodus:		.byte 1
Bereitschaft:		.byte 1
Zustand:		.byte 1
	.cseg										; dies ist Code

; ----- Platz um .equ definitionen vorzunehmen
#ifdef DEBUG 
.equ	T1Counter = 10							; Debug-Timer-Wert f�r xxs
#else
.equ	T1Counter = 98							; Timer-Wert f�r 0,1s
#endif
.equ Timer=5									; Zeit zum Warten 0,5s

;----- Ampelzust�nde Auto = A, Fu�g�nger = F
.equ A_gruen_F_rot = 0x11	
.equ A_gelb_F_rot = 0x12
.equ A_rot_F_rot = 0x14
.equ A_rot_F_gruen = 0x0C
.equ A_rotgelb_F_rot = 0x16
.equ A_F_aus = 0x00

; ----- Programm beginnt hinter der Vektortabelle: -----
	.org 4*INT_VECTORS_SIZE
; hier kommen die Interrupt Service Routinen hin, wenn benutzt
/********************************************************/
;	ISR External Interrupt 0: PCINT0 

;---- Tasterabfrage ----
PCINT0_isr:	
	push r16	
	ldi R16,0x00								; 0 = Nachtmodus aktiv
	sbis PINA,5
	sts Nachtmodus, R16							; Nachtmodus an
	
	ldi R16,0x01								; 1 = Nachtmodus inaktiv
	sbis PINA,6
	sts Nachtmodus, R16							; Nachtmodus aus
	
	sbis PINA,7
	call BereitschaftPruefen					; Bereitschaft an
	
	pop r16										; Register wiederherstellen
	reti										; Return from Interrupt;

BereitschaftPruefen:
	push R16
	push R17
	push R18

	lds R16, Zustand
	ldi R17, 0x05
	ldi R18, 0x01

	cp R16,R18									; Pr�fen ob wir <= Zustand 1 sind
	brge BereitschaftAn
	cp R17,R16									; Pr�fen ob wir >= Zustand 5 sind
	brge BereitschaftAn

	pop R18
	pop R17
	pop R16
	ret

BereitschaftAn:
	ldi R16,0x01
	sts Bereitschaft, R16

	pop R18
	pop R17
	pop R16
	ret
	

/********************************************************/
;	ISR Timer1 Compare Interrupt A
OCRA1A_isr:
	push r16									; Register auf den Stack retten
   	in   r16, SREG								; Statusregister zum Sichern nach R16
	
	push r16									; und auf den Stack
	lds r16, T1count							; Z�hlwert lesen

	tst r16										; schon Null ?	
	breq noDec									; ja: nichts weiter Abziehen
	dec r16										; T1count--
	sts T1count, r16							; und abspeichern

noDec:
	pop r16										; die Statusregister von Stack holen
	out SREG, r16								; und wieder herstellen
	pop r16										; Register wiederherstellen
	reti										; Return from Interrupt;
;

; ----- Initialisierung des PCINT0-----
InitPCINT0:
	push r16
	push r17
	
	ldi R16 , 0x01								; Setze Die PINA(7..0) als external Interrupt
	sts PCICR, R16
	ldi R16, 0xE0								; Setze PINA(5,6,7)
	sts PCMSK0, R16
			
	pop r17
	pop r16
	ret
;

; ----- Initialisierung von Timer1 auf 0,1s Periode -----
InitTimer1:
	; beim 644PA sind Timer1-Register Memory.mapped
	push r17
	ldi r17, HIGH(T1Counter)					; Timer-Schwelle 
	sts OCR1AH, r17								; byte-weise 
	ldi r17, LOW(T1Counter)						; nach OCR1A
	sts OCR1AL, r17
	clr r17										; r17=0 
	sts TCNT1H, r17								; Counter=0
	sts TCNT1L, r17
	sts TCCR1A, r17								; configure to CTC-Mode	
#ifdef DEBUG 
	ldi r17, 0b0001010							; CTC-mode, prescaler 8 f�r DEBUG 
#else 
	ldi r17, 0b0001101							; CTC-mode, prescaler 1024 
#endif
	sts TCCR1B, r17				
	; und den OC1A Interrupt einschalten:
	lds r17, TIMSK1								; Interruptmaske Timer1 
	ori r17, 0b00000010							; OCIE1A setzen
	sts TIMSK1, r17								; und abspeichern
	pop r17
	ret

; ----- Warte-Z�hler Setzen und Starten (nonblocking)
startWait:
	ldi R16,Timer
	sts T1count, r16							; Nur Z�hler setzen
	ret

; ----- Wait-funktion komplett
; Parameter: R16 enth�lt die Wartedauer in Zehntelsekunden

wait:
; Timer resetten, Interrupt aktivieren
	ldi R16,Timer
	sts T1count, r16		

; ----- Rest der Komplett-Funktion als Abwarte-Funktion -----
waitNow:
; polling auf Counter=0
	lds r16, T1count
	tst r16
	brne waitNow
	ret
;

; ***** Einsprungpunkt in das Hauptprogramm *****

Main:
; ----- Initialisierung der grundlegenden Funktionen -----
	; Initialisieren des Stacks am oberen Ende des RAM
	; 16 bit SP wird als SPH:SPL im IO-Space angesprochen 
    
	ldi r16, LOW(RAMEND)					; low-Byte von RAMEND nach r16
	out SPL, r16							; in low-byte des SP ausgeben
											; der SP liegt im IO-Space 
    	ldi r16, HIGH(RAMEND)				; high-Byte von RAMEND nach r16
    	out SPH, r16						; in high-byte des SP ausgeben
    
	; ab hier kann der Stack verwendet werden 

	call InitPCINT0							; PCINT0 auf PINA 5,6,7 initialisieren
	call InitTimer1							; Timer1 initialisieren
	sei										; global Interrupt enable
	
	ldi R16,0x01							; Wir beginnen mit Nachtmodus aus
	sts Nachtmodus, R16		
	
	ldi R16, 0x1F
	out DDRA,R16							; Vorbereiten der Ausg�nge
	
	ldi R16,0xE0
	out PORTA, R16							; Pull up Widerst�nde f�r PINA 5,6,7 aktivieren
	nop										; Bitte die PINA 5,6,7 aktivieren f�r PULL up Hinweis aus dem Mikrocontroller.net Forum
 
Start:
	ldi R17,0x00
	lds R18,Nachtmodus	
	cp R18,R17
	brne Zustand1

Zustand0:
	ldi R18, A_F_aus
	out PORTA, R18							; Alle aus
	
	ldi R17,0x00
	sts Zustand,R17							; Zustand setzen auf Zustand0
	
	lds R18,Bereitschaft	
	cp R18,R17								; Pr�fen auf 0, ob Bereitschaft gedr�ckt wurde 
	breq Zustand1							; Wenn ja gehe zu  Zustand2
	jmp Start

Zustand1:
	ldi R18, A_gruen_F_rot	
	out PORTA,  R18
	
	ldi R17,0x01
	sts Zustand,R17							; Zustand setzen auf Zustand1
	
	lds R18,Bereitschaft
	cp R18,R17								; Pr�fen (auf 0), ob Bereitschaft gedr�ckt wurde
	breq Zustand2							; Wenn ja, gehe zu  Zustand2
	jmp Start								; Ansonsten erneut pr�fen

Zustand2:
	call Wait
	ldi R16,0x00
	sts Bereitschaft,R16
	
	ldi R18, A_gelb_F_rot
	out PORTA, R18

	inc R17
	sts Zustand,R17

Zustand3:
	call Wait
	ldi R18, A_rot_F_rot
	out PORTA, R18
	
	inc R17
	sts Zustand,R17

Zustand4:
	call Wait
	ldi R18, A_rot_F_gruen
	out PORTA, R18

	inc R17
	sts Zustand,R17

Zustand5:
	call Wait
	ldi R18, A_rot_F_rot
	out PORTA, R18

	inc R17
	sts Zustand,R17

Zustand6:
	call Wait
	ldi R18, A_rotgelb_F_rot
	out PORTA, R18
	
	inc R17
	sts Zustand,R17

Zustand7:
	call Wait
	ldi R18, A_gruen_F_rot
	out PORTA, R18
	
	inc R17
	sts Zustand, R17

Zustand8:
	call Wait
	ldi R18, A_gruen_F_rot
	out PORTA, R18

	inc R17
	sts Zustand, R17
	call Wait
	jmp Start
