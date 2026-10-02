
;===========================================================================
; TP4/TP5: Contador Numérico con Teclado (HARDWARE REAL)
; Cátedra: Electrónica Digital II - UNC
; Oscilador: Cristal externo de 4 MHz -> Tcy = 1 us
;===========================================================================

    LIST      P=16F887
    #INCLUDE <P16F887.INC>

    __CONFIG _CONFIG1, _FOSC_XT & _WDTE_OFF & _PWRTE_ON & _MCLRE_ON & _CP_OFF & _CPD_OFF & _BOREN_OFF & _IESO_OFF & _FCMEN_OFF & _LVP_OFF
    __CONFIG _CONFIG2, _WRT_OFF & _BOR21V

;---------------------------------------------------------------------------
; Variables en Banco 0
;---------------------------------------------------------------------------
    CBLOCK 0x20
        UNI           ; Unidades (0-9)
        DEC           ; Decenas  (0-9)
        CEN           ; Centenas (0-9)
        MIL           ; Unidades de mil (0-9)
        MUX_IDX       ; Índice del display activo (0 a 3)
        CONT_VEL      ; Acumulador para la velocidad del contador (100ms)
        ESTADO        ; 0 = detenido, 1 = contando
        D1, D2        ; Registros para retardo antirrebote
        RST_PROC      ; Control de rebote para botón RESET
        START_PROC    ; Control de rebote para botón START/STOP
        TECLA_VAL     ; Valor numérico de la tecla presionada
        TECLADO_FLAG  ; Bandera para evitar autorepetición al mantener tecla
    ENDC

;---------------------------------------------------------------------------
; Variables en RAM Compartida / Unbanked (0x70 - 0x7F)
;---------------------------------------------------------------------------
    CBLOCK 0x70
        W_TEMP        ; Copia de W durante la ISR
        STATUS_TEMP   ; Copia de STATUS durante la ISR
    ENDC

;---------------------------------------------------------------------------
; Vectores de Inicio e Interrupción
;---------------------------------------------------------------------------
    ORG 0x0000
    GOTO INICIO

    ORG 0x0004
    GOTO ISR

;===========================================================================
; TABLA DE DECODIFICACION 7 SEGMENTOS (Cátodo Común)
;===========================================================================
    ORG 0x0010        ; Ubicada de forma segura
TABLA_7SEG:
    ADDWF   PCL, F
    RETLW   B'00111111'   ; 0
    RETLW   B'00000110'   ; 1
    RETLW   B'01011011'   ; 2
    RETLW   B'01001111'   ; 3
    RETLW   B'01100110'   ; 4
    RETLW   B'01101101'   ; 5
    RETLW   B'01111101'   ; 6
    RETLW   B'00000111'   ; 7
    RETLW   B'01111111'   ; 8
    RETLW   B'01101111'   ; 9

;===========================================================================
; INICIALIZACION
;===========================================================================
INICIO:
    ; Configurar pines como puramente digitales
    BANKSEL ANSEL
    CLRF    ANSEL     ; PORTA/E digitales (necesario para RA0-RA3)
    CLRF    ANSELH    ; PORTB digital (necesario para RB0-RB7)

    ; Configurar dirección de puertos (Entradas/Salidas)
    BANKSEL TRISA
    MOVLW   B'11110000'
    MOVWF   TRISA     ; RA0 a RA3 = Salidas (Filas del teclado)
    
    BANKSEL TRISD
    CLRF    TRISD     ; PORTD = Salidas (Segmentos)
    CLRF    TRISC     ; PORTC = Salidas (Control Cátodos/Transistores)

    BANKSEL TRISB
    MOVLW   B'11110011'
    MOVWF   TRISB     ; RB4-RB7 = Entradas (Columnas teclado), RB0, RB1 = Entradas (Botones)

    ; Configuración de Option Register: Pull-ups ON, Prescaler Timer0 1:8
    BANKSEL OPTION_REG
    MOVLW   B'00000010' ; Pull-ups ON, T0CS=0, PS=010 (1:8)
    MOVWF   OPTION_REG

    ; Configurar Habilitación de Pull-ups individuales de Puerto B
    BANKSEL WPUB
    MOVLW   B'11110011'
    MOVWF   WPUB      ; Activa Pull-ups en columnas del teclado y botones

    ; Precarga Timer0 para multiplexado (~2 ms por interrupción)
    BANKSEL TMR0
    MOVLW   .6
    MOVWF   TMR0

    BANKSEL PORTD
    CLRF    PORTD
    CLRF    PORTC     ; Apaga las bases de los transistores (0V)
    
    MOVLW   0x0F
    MOVWF   PORTA     ; Pone filas de teclado en alto (Inactivas por defecto)

    ; Estado inicial de variables
    CLRF    UNI
    CLRF    DEC
    CLRF    CEN
    CLRF    MIL
    CLRF    MUX_IDX
    CLRF    CONT_VEL
    CLRF    ESTADO
    CLRF    RST_PROC
    CLRF    START_PROC
    CLRF    TECLADO_FLAG

    ; Habilitar SOLO Interrupción de Timer0
    MOVLW   B'10100000' ; GIE=1, T0IE=1, INTE=0
    MOVWF   INTCON

;===========================================================================
; BUCLE PRINCIPAL (Sondeo de botones y teclado)
;===========================================================================
LAZO_PRINCIPAL:
    CALL    SONDEAR_START
    CALL    SONDEAR_RESET
    CALL    LEER_TECLADO
    GOTO    LAZO_PRINCIPAL

;===========================================================================
; LECTURA DEL TECLADO MATRICIAL (RA0-RA3 Filas, RB4-RB7 Columnas)
;===========================================================================
LEER_TECLADO:
    MOVF    ESTADO, F
    BTFSS   STATUS, Z
    RETURN              ; Si está contando (ESTADO = 1), ignora el teclado

    ; --- Escaneo Fila 1 (RA0 = 0) ---
    MOVLW   B'00001110'
    MOVWF   PORTA
    NOP                 ; Pequeño retardo de estabilización
    BTFSS   PORTB, 4
    GOTO    TECLA_1
    BTFSS   PORTB, 5
    GOTO    TECLA_2
    BTFSS   PORTB, 6
    GOTO    TECLA_3

    ; --- Escaneo Fila 2 (RA1 = 0) ---
    MOVLW   B'00001101'
    MOVWF   PORTA
    NOP
    BTFSS   PORTB, 4
    GOTO    TECLA_4
    BTFSS   PORTB, 5
    GOTO    TECLA_5
    BTFSS   PORTB, 6
    GOTO    TECLA_6

    ; --- Escaneo Fila 3 (RA2 = 0) ---
    MOVLW   B'00001011'
    MOVWF   PORTA
    NOP
    BTFSS   PORTB, 4
    GOTO    TECLA_7
    BTFSS   PORTB, 5
    GOTO    TECLA_8
    BTFSS   PORTB, 6
    GOTO    TECLA_9

    ; --- Escaneo Fila 4 (RA3 = 0) ---
    MOVLW   B'00000111'
    MOVWF   PORTA
    NOP
    BTFSS   PORTB, 5    ; El cero suele estar en el medio (Columna 2)
    GOTO    TECLA_0

    ; --- Si ninguna tecla está presionada ---
    BCF     TECLADO_FLAG, 0 ; Libera la bandera para permitir una nueva pulsación
    MOVLW   0x0F
    MOVWF   PORTA           ; Deja las filas en alto (inactivas)
    RETURN

; --- Rutinas de asignación de valor numérico (CORREGIDAS) ---
TECLA_1:
    MOVLW   .1
    GOTO    PROCESAR_TECLA
TECLA_2:
    MOVLW   .2
    GOTO    PROCESAR_TECLA
TECLA_3:
    MOVLW   .3
    GOTO    PROCESAR_TECLA
TECLA_4:
    MOVLW   .4
    GOTO    PROCESAR_TECLA
TECLA_5:
    MOVLW   .5
    GOTO    PROCESAR_TECLA
TECLA_6:
    MOVLW   .6
    GOTO    PROCESAR_TECLA
TECLA_7:
    MOVLW   .7
    GOTO    PROCESAR_TECLA
TECLA_8:
    MOVLW   .8
    GOTO    PROCESAR_TECLA
TECLA_9:
    MOVLW   .9
    GOTO    PROCESAR_TECLA
TECLA_0:
    MOVLW   .0
    GOTO    PROCESAR_TECLA

PROCESAR_TECLA:
    MOVWF   TECLA_VAL       ; Guarda el número presionado
    MOVLW   0x0F
    MOVWF   PORTA           ; Restaura filas para evitar cruces
    
    BTFSC   TECLADO_FLAG, 0
    RETURN                  ; Si ya se procesó esta tecla sostenida, ignora

    BSF     TECLADO_FLAG, 0 ; Marca que se presionó una tecla válida

    ; Desplaza los dígitos hacia la izquierda al estilo calculadora
    MOVF    CEN, W
    MOVWF   MIL
    MOVF    DEC, W
    MOVWF   CEN
    MOVF    UNI, W
    MOVWF   DEC
    MOVF    TECLA_VAL, W
    MOVWF   UNI
    RETURN

;===========================================================================
; RUTINAS DE BOTONES CON ANTIRREBOTE POR SOFTWARE
;===========================================================================
SONDEAR_START:
    BTFSC   PORTB, 0
    GOTO    RB0_LIBERADO
    CALL    RETARDO_20MS
    BTFSC   PORTB, 0
    RETURN
    BTFSC   START_PROC, 0
    RETURN
    BSF     START_PROC, 0
    MOVLW   .1
    XORWF   ESTADO, F       ; Alterna el estado (Pausa/Cuenta)
    RETURN
RB0_LIBERADO:
    BCF     START_PROC, 0
    RETURN

SONDEAR_RESET:
    BTFSC   PORTB, 1
    GOTO    RB1_LIBERADO
    CALL    RETARDO_20MS
    BTFSC   PORTB, 1
    RETURN
    BTFSC   RST_PROC, 0
    RETURN
    BSF     RST_PROC, 0
    MOVF    ESTADO, F
    BTFSS   STATUS, Z
    RETURN                  ; Si está contando (ESTADO != 0), ignora el Reset

    ; Resetear contador a 0000
    CLRF    UNI
    CLRF    DEC
    CLRF    CEN
    CLRF    MIL
    RETURN
RB1_LIBERADO:
    BCF     RST_PROC, 0
    RETURN

;===========================================================================
; RETARDO_20MS
;===========================================================================
RETARDO_20MS:
    MOVLW   .26
    MOVWF   D1
R20_L1:
    MOVLW   .248
    MOVWF   D2
R20_L2:
    DECFSZ  D2, F
    GOTO    R20_L2
    DECFSZ  D1, F
    GOTO    R20_L1
    RETURN

;===========================================================================
; RUTINA DE INTERRUPCION (ISR) - Solo Timer0
;===========================================================================
ISR:
    MOVWF   W_TEMP
    SWAPF   STATUS, W
    CLRF    STATUS
    MOVWF   STATUS_TEMP

    ; Recarga de Timer0
    MOVLW   .6
    ADDWF   TMR0, F
    BCF     INTCON, T0IF

    ; Refresco del display (cada 2 ms)
    CALL    REFRESCAR_DISPLAY

    ; Conteo de tiempo (Velocidad del contador: 50 x 2ms = 100ms)
    INCF    CONT_VEL, F
    MOVLW   .50
    XORWF   CONT_VEL, W
    BTFSS   STATUS, Z
    GOTO    FIN_ISR

    CLRF    CONT_VEL
    CALL    ACTUALIZAR_CONTADOR

FIN_ISR:
    SWAPF   STATUS_TEMP, W
    MOVWF   STATUS
    SWAPF   W_TEMP, F
    SWAPF   W_TEMP, W
    RETFIE

;===========================================================================
; REFRESCAR_DISPLAY (CORREGIDO PARA TRANSISTORES NPN)
;===========================================================================
REFRESCAR_DISPLAY:
    CLRF    PORTC

    MOVF    MUX_IDX, W
    XORLW   .0
    BTFSC   STATUS, Z
    GOTO    SHOW_UNI

    MOVF    MUX_IDX, W
    XORLW   .1
    BTFSC   STATUS, Z
    GOTO    SHOW_DEC

    MOVF    MUX_IDX, W
    XORLW   .2
    BTFSC   STATUS, Z
    GOTO    SHOW_CEN

    GOTO    SHOW_MIL

SHOW_UNI:
    MOVF    UNI, W
    CALL    TABLA_7SEG
    MOVWF   PORTD
    BSF     PORTC, 0
    GOTO    NEXT_MUX

SHOW_DEC:
    MOVF    DEC, W
    CALL    TABLA_7SEG
    MOVWF   PORTD
    BSF     PORTC, 1
    GOTO    NEXT_MUX

SHOW_CEN:
    MOVF    CEN, W
    CALL    TABLA_7SEG
    MOVWF   PORTD
    BSF     PORTC, 2
    GOTO    NEXT_MUX

SHOW_MIL:
    MOVF    MIL, W
    CALL    TABLA_7SEG
    MOVWF   PORTD
    BSF     PORTC, 3

NEXT_MUX:
    INCF    MUX_IDX, F
    MOVLW   .4
    XORWF   MUX_IDX, W
    BTFSS   STATUS, Z
    RETURN
    CLRF    MUX_IDX
    RETURN

;===========================================================================
; ACTUALIZAR_CONTADOR: Incrementa secuencialmente en Base 10
;===========================================================================
ACTUALIZAR_CONTADOR:
    MOVF    ESTADO, F
    BTFSS   STATUS, Z
    GOTO    INC_UNI
    RETURN                  ; Si está detenido, no suma

INC_UNI:
    INCF    UNI, F
    MOVLW   .10             
    XORWF   UNI, W
    BTFSS   STATUS, Z
    RETURN
    CLRF    UNI

    INCF    DEC, F
    MOVLW   .10             
    XORWF   DEC, W
    BTFSS   STATUS, Z
    RETURN
    CLRF    DEC

    INCF    CEN, F
    MOVLW   .10             
    XORWF   CEN, W
    BTFSS   STATUS, Z
    RETURN
    CLRF    CEN

    INCF    MIL, F
    MOVLW   .10             
    XORWF   MIL, W
    BTFSS   STATUS, Z
    RETURN
    CLRF    MIL
    RETURN

    END