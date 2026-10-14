assembly_return_site:
  # Save the stack info
  sub sp, sp, #0x10
  stp x29, x30, [sp]
  # Set exit code
  mov x0, #0
  bl exit
  # Restore stack info
  ldp x29, x30, [sp]
  add sp, sp, #0x10
  ret
