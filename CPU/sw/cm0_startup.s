.syntax unified
    .arch armv6-m

    .equ stack_top, 0x00001000

    .section INTERRUPT_VECTOR, "a", %progbits
    .align 2
    .global __isr_vector
 __isr_vector:
    .long stack_top
    .long Reset_Handler /*Reset*/
    .long 0             /**/
    .long 0             /**/
    .long 0             /**/
    .long 0             /**/
    .long 0             /**/
    .long 0             /**/
    .long 0             /**/
    .long 0             /**/
    .long 0             /**/
    .long 0             /**/
    .long 0             /**/
    .long 0             /**/
    .long 0             /**/
    .long 0             /**/

    /* External Interrupt */

    .long 0  /**/
    .long 0             /**/
    .long 0             /**/
    .long 0             /**/
    .long 0             /**/
    .long 0             /**/
    .long 0             /**/
    .long 0             /**/
    .long 0             /**/
    .long 0             /**/
    .long 0             /**/
    .long 0             /**/
    .long 0             /**/
    .long 0             /**/
    .long 0             /**/
    .long 0             /**/

    .size   __isr_vector, . - __isr_vector

    .text
    .thumb
    .thumb_func
    .align  1
    .globl  Reset_Handler
    .type   Reset_Handler, %function
Reset_Handler:
    bl _start

    .pool
    .size   Reset_Handler, . - Reset_Handler

_start:
    bl      main
again:
    b again

/*  Interrupt Handler */
    .text
    .thumb
    .thumb_func
    .align  1
    .globl  _int_handler
    .type   _int_handler, %function
//_int_handler:
//    push  {lr}
//    bl __irq_hanlder_0
//    pop   {pc}

//    .end
