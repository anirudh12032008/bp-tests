OUTPUT_ARCH(riscv)
ENTRY(_start)

SECTIONS
{
  . = 0x80000000;
  .text : { *(.text.init) *(.text*) }
  .rodata : { *(.rodata*) }
  .bss : { *(.bss*) *(COMMON) }

  . = 0x80010000;
  .pt : { *(.pt) }

  /DISCARD/ : { *(*) }
}
