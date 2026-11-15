# Minimal regression: misaligned load crossing a page boundary, first page
# unmapped.  A conforming core takes exactly one load exception with mepc
# pointing at the faulting load.  BlackParrot instead re-delivers the page
# fault on the first instruction of the trap handler, so mepc becomes mtvec.
#
# Build variants:
#   (default)              FAULT_VA = 0x80002ff9  (misaligned crossing)
#   -DCONTROL_ALIGNED      FAULT_VA = 0x80002000  (aligned, same unmapped page)
#
# The program terminates through BlackParrot's host "finish" MMIO register:
# store 0 -> PASS, store nonzero -> FAIL.

#ifndef CONTROL_ALIGNED
    .equ FAULT_VA, 0x80002ff9
#else
    .equ FAULT_VA, 0x80002000
#endif

    .section .text.init, "ax"
    .globl _start
_start:
    li      s9, 0                   # handler entry counter
    li      s0, 0
    li      s1, 0
    li      s2, 0
    li      s3, 0
    li      s4, 0
    li      s5, 0
    li      s6, 0
    li      s7, 0

    la      t0, trap_handler
    csrw    mtvec, t0
    csrw    medeleg, zero
    csrw    mideleg, zero

    # Sv39 tables: root[2] -> L1[0] -> L0.
    la      t1, pt_root
    li      t2, 0x20004401          # root[2] -> L1 at 0x80011000, V
    sd      t2, 16(t1)

    la      t1, pt_l1
    li      t2, 0x20004801          # L1[0] -> L0 at 0x80012000, V
    sd      t2, 0(t1)

    la      t1, pt_l0
    li      t2, 0x200000CF          # VA 0x80000000 -> PA 0x80000000, 4K
    sd      t2, 0(t1)               # V|R|W|X|U|G, A=0, D=0
    li      t2, 0x200004CF          # VA 0x80001000 -> PA 0x80001000, 4K
    sd      t2, 8(t1)
    # L0[2] (VA 0x80002000) deliberately left invalid.

    li      t0, 0x8000000000080010  # satp: Sv39, PPN 0x80010
    csrw    satp, t0
    sfence.vma

    li      t0, 0x800               # mstatus.MPP = S
    csrs    mstatus, t0
    la      t0, smode_entry
    csrw    mepc, t0
    mret

    .align 2
smode_entry:
    ecall                           # trap 1: S-mode ecall
1:  ecall                           # trap 2: ecall after mret, proves MPP=S
    li      t4, FAULT_VA
fault_insn:
    ld      t5, 0(t4)               # trap 3: the faulting load
2:  j       2b                      # not reached

    .align 2
    .globl trap_handler
trap_handler:
    addi    s9, s9, 1               # first handler instruction: no memory access
    csrr    t0, mepc
    csrr    t1, mcause
    csrr    t2, mtval
    csrr    t3, mstatus

    li      t4, 1
    beq     s9, t4, handle_ecall1
    li      t4, 2
    beq     s9, t4, handle_ecall2
    j       handle_load

handle_ecall1:
    mv      s0, t0                  # mepc
    mv      s1, t1                  # mcause
    mv      s2, t3                  # mstatus (MPP)
    addi    t0, t0, 4               # skip ecall
    csrw    mepc, t0
    mret

handle_ecall2:
    mv      s3, t1                  # mcause (must be 9 for S-mode ecall)
    mv      s7, t0                  # mepc
    addi    t0, t0, 4
    csrw    mepc, t0
    li      t3, 0x1000
    csrc    mstatus, t3             # MPP = S for the load phase
    li      t3, 0x800
    csrs    mstatus, t3
    mret

handle_load:
    mv      s4, t0                  # observed mepc
    mv      s5, t1                  # observed mcause
    mv      s6, t2                  # observed mtval

    la      t6, fault_insn
    li      t5, 0                   # 0 = conforming, 1 = bug
    bne     t0, t6, report_bug
    li      t4, 4                   # load address misaligned
    beq     t1, t4, check_mtval
    li      t4, 13                  # load page fault
    bne     t1, t4, report_bug
check_mtval:
    li      t4, FAULT_VA
    bne     t2, t4, report_bug
    j       report
report_bug:
    li      t5, 1
report:
    li      t0, 0x00102000          # BlackParrot host finish register
    sd      t5, 0(t0)
3:  j       3b

    .section .pt, "aw", @progbits
    .align 12
    .globl pt_root
pt_root:    .zero 0x1000
    .globl pt_l1
pt_l1:      .zero 0x1000
    .globl pt_l0
pt_l0:      .zero 0x1000
