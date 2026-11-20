# RSDP VHDL reference implementation

This VHDL source code implements a RSDP (RISC-V Serial Debug Protocol) transport module.

**WARNING:**
This source code implements the **work-in-progress** RISC-V RSDP specification.
Please note that this specification is **preliminary** and subject to future changes.

The source code has the following files:

- `riscv_rsdp_pkg.vhd`
  VHDL Package with common constants and types for RSDP
- `riscv_rsdp_escape.vhd`
  VHDL module to detect Escape Sequences
- `riscv_rsdp_transport.vhd`
  VHDL module which implements a RSDP transport module.
  This module instantiates `riscv_rsdp_escape` to detect escape sequences.
  This module is the toplevel entity which implements a RSDP transport.
- `riscv_rsdp_ioreg.vhd`
  VHDL module which implements IO registers.
  These flop flops should be put as close as possible to the DATA pin.
- `riscv_rsdp_sp.vhd`
  VHDL module to convert the single-pin variant of the protocol to regular RSDP, uses `riscv_rsdp_sp_*.vhd` as submodules.
- `riscv_jtag_backend_sim.vhd`
  VHDL module used for verification to simulate a DMI bus manager.
- `riscv_rsdp_escape_tb.vhd`
  Testbench to verify functionality of `riscv_rsdp_escape`
- `riscv_rsdp_transport_tb.vhd`
  Testbench to verify functionality of `riscv_rsdp_transport`

## Simulation

The testbenches should work with any kind of VHDL simulator (like for example `Questa`).

The testbenches can be simulated with `nvc` (https://github.com/nickg/nvc).
For example

```
nvc -a riscv_rsdp_pkg.vhd
nvc -a riscv_jtag_backend_sim.vhd
nvc -a riscv_rsdp_escape.vhd
nvc -a riscv_rsdp_ioreg.vhd
nvc -a riscv_rsdp_transport.vhd
nvc -a riscv_rsdp_transport_tb.vhd
nvc -e riscv_rsdp_transport_tb
nvc -r riscv_rsdp_transport_tb --format=fst --wave=riscv_rsdp_transport_tb.fst
```

## License

This source code is published under the MIT License. See `license.txt` and comments in source code.
