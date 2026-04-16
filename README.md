# Programmable Memory Built-In Self-Test (MBIST) IP

A **SystemVerilog-based programmable Memory Built-In Self-Test (MBIST)** IP designed around a **dual-port RAM** model. The design is controlled through a **CSR register map** and supports runtime configuration of the test address range, March algorithm selection, background looping, stop-on-fail behavior, and optional signature checking. It was functionally verified in **QuestaSim** using a CSR-driven testbench with fault injection, and synthesized in **Synopsys Design Compiler** for area, timing, and power analysis. :contentReference[oaicite:0]{index=0}

## Overview

Embedded memories are a common source of manufacturing defects and in-field reliability issues. This project implements a programmable MBIST IP that can be configured at runtime and used to systematically test a dual-port RAM using well-known March-based memory test algorithms. The design reports pass/fail status, captures first-fail debug information, and generates a compact 16-bit MISR/CRC-style signature of executed memory operations. :contentReference[oaicite:1]{index=1}

## Features

- Programmable MBIST around a dual-port RAM
- CSR-controlled runtime configuration
- Configurable address range
- Support for multiple March algorithms:
  - **MATS+**
  - **MATS++**
  - **March C-**
- Optional multiple background runs
- Stop-on-fail option
- Go / no-go status reporting
- First-fail capture:
  - failing address
  - expected data
  - observed data
- 16-bit MISR/CRC-style signature compaction
- Signature checking against an expected signature register
- Takeover mode for exclusive RAM access during test
- Directed verification with fault injection in QuestaSim
- Synthesis flow in Synopsys Design Compiler with area/timing/power reports :contentReference[oaicite:2]{index=2}

## Architecture

The main blocks are:

- **Dual-Port RAM (`dp_ram.sv`)**  
  Memory under test with two independent ports. One port is used for normal or MBIST-driven accesses, while the other can be used by the testbench for initialization and fault injection. :contentReference[oaicite:3]{index=3}

- **MBIST Core (`mbist_core_v3.sv`)**  
  Executes the selected March algorithm, traverses the configured memory range, compares read data, captures first-fail information, and updates the MISR/CRC-style signature. :contentReference[oaicite:4]{index=4}

- **CSR Wrapper (`mbist_csr_wrap_v3.sv`)**  
  Provides the register programming model and arbitrates access to the RAM data port between the normal master and the MBIST core. During MBIST execution, the wrapper enters takeover mode and blocks normal accesses. :contentReference[oaicite:5]{index=5}

- **System Top (`mbist_system_top.sv`)**  
  Convenience top module integrating the wrapper and RAM together for synthesis or quick top-level simulation. :contentReference[oaicite:6]{index=6}

## Project Structure

```text
HW1_project/
├── dp_ram.sv
├── mbist_core_v3.sv
├── mbist_csr_wrap_v3.sv
├── mbist_system_top.sv
├── tb_mbist_csr_wrap_v3.sv
├── synth_mbist_wrap_v3.tcl
├── synth_mbist_system_v3.tcl
├── run_questa_mbist.sh
├── run_dc_mbist.sh
└── mbist_optional_integration/
