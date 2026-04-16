# Programmable Memory Built-In Self-Test (MBIST) IP

A **SystemVerilog-based programmable Memory Built-In Self-Test (MBIST)** IP developed around a **dual-port RAM** model. The project focuses on building a configurable and verification-driven MBIST architecture that can be programmed at runtime through a **CSR register map**, execute multiple **March-based memory test algorithms**, capture detailed debug information on failures, and provide synthesis results for implementation analysis. Functional verification was carried out in **QuestaSim** using a CSR-driven testbench with fault injection, while hardware-oriented implementation metrics were obtained using **Synopsys Design Compiler**.

## Why This Project Matters

Embedded memories are among the most defect-prone structures in digital systems, both in manufacturing and in-field operation. MBIST is a widely used design-for-testability technique that allows a system to verify memory integrity without relying on external test equipment during normal use. This project demonstrates not only the RTL implementation of an MBIST engine, but also the broader engineering workflow around it: **programmability, verification, fault injection, debug visibility, and synthesis analysis**. 

Unlike a basic fixed-pattern memory tester, this design is **runtime-configurable**, meaning the tested address range, algorithm choice, background behavior, and fail-handling strategy can all be changed without resynthesis. That makes it closer to how reusable MBIST IP is treated in real SoC design flows. 

## Key Highlights

- Designed a **programmable MBIST IP** around a dual-port RAM model
- Implemented **CSR-controlled runtime configuration** for test setup
- Supported multiple March-style algorithms:
  - **MATS+**
  - **MATS++**
  - **March C-**
- Added **first-fail debug capture**, including:
  - failing address
  - expected data
  - observed data
- Generated a **16-bit MISR/CRC-style signature** as a compact fingerprint of test execution
- Implemented **takeover mode**, where the MBIST temporarily gains exclusive control of the RAM data port during test execution
- Built a **directed CSR-driven verification testbench** in QuestaSim
- Demonstrated **fault injection** to validate failure detection and debug reporting
- Performed **synthesis in Synopsys Design Compiler** and analyzed area, timing, and dynamic power :contentReference[oaicite:3]{index=3}

## Main Capabilities

This MBIST design supports several practical capabilities typically expected from configurable test IP:

### 1. Runtime Programmability
The MBIST is configured through control and status registers rather than hardcoded parameters. This allows changing the address window under test, selecting the algorithm, enabling multiple backgrounds, activating signature checking, and choosing whether the test should stop immediately on failure. 

### 2. Multiple Algorithm Support
The core supports three March-style memory test algorithms:

- **MATS+**
- **MATS++**
- **March C-**

These algorithms differ in operation order, complexity, and coverage, and the project demonstrates that the implementation can select among them dynamically at runtime. Verification results show that different algorithms lead to different execution lengths and different signatures, as expected.

### 3. First-Fail Debug Visibility
On the first detected mismatch, the MBIST captures:

- the failing address
- the expected value
- the observed value

This is an important practical feature because it makes the design useful not only for pass/fail testing, but also for **debugging and diagnosis**.

### 4. Signature Compaction
The MBIST generates a **16-bit MISR/CRC-like signature** using polynomial `0x1021`, compacting the history of memory operations into a lightweight fingerprint. This is useful for regression checking in simulation and for low-overhead hardware-level validation when compared against an expected signature.

### 5. Controlled Memory-Port Arbitration
During MBIST execution, the wrapper blocks normal accesses and routes the RAM interface to the MBIST core. This “takeover mode” models a realistic SoC integration pattern where test logic temporarily owns the memory interface until the test is complete.

## Architecture Overview

The design is organized into four main modules:

### `dp_ram.sv`
A dual-port RAM model that acts as the memory under test. It supports byte enables and exposes two independent ports. In the verification environment, one port is used for normal or MBIST-driven access, while the other can be used by the testbench for controlled initialization and fault injection.

### `mbist_core_v3.sv`
The central MBIST engine. This module executes the selected March algorithm across the configured address range, handles read/write sequencing, compares expected versus observed data, captures the first failure, and updates the signature register.

### `mbist_csr_wrap_v3.sv`
A CSR wrapper that turns the MBIST core into a programmable peripheral. It implements the register map, generates the start pulse, manages takeover arbitration, and latches status, signature, and error information for software-visible access.
### `mbist_system_top.sv`
A convenience top-level module that instantiates both the wrapper and the RAM together. This allows end-to-end synthesis and easier top-level experimentation. 

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
