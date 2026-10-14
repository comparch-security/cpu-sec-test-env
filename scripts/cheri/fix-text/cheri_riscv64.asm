assembly_return_site:
  # Save the stack info
  addi sp, sp, -16
  sd ra, 8(sp)
  sd s0, 0(sp)
  # Set exit code
  li a0, 0
  call exit
  # Restore stack info
  ld s0, 0(sp)
  ld ra, 8(sp)
  addi sp, sp, 16
  ret
