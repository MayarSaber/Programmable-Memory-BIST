# MBIST Power-On Functional Testbench Demo (Minimal)

This is a trimmed project that demonstrates the *optional requirement*:
> Integrate the MBIST in a functional testbench and enable it at power-on.

## What happens at power-on
The testbench (`tb/core/tb_top.sv`) does:
1. `fetch_enable = 0` (CPU held idle)
2. Programs MBIST CSRs: STARTADR / ENDADR / CTRL
3. Polls STATUS until DONE
4. If PASS: loads firmware into `dp_ram` using `$readmemh`
5. `fetch_enable = 1` (CPU starts execution)

## How to run (Questa/ModelSim)
From `tb/core`:

```bash
./run_vsim.sh
```

Optional plusargs:
- Limit MBIST range (default tests first 16KB):
  - `+mbist_end=00003ffc`
- Select algorithm:
  - `+mbist_algo=0` (MATS+)
  - `+mbist_algo=1` (MATS++)
  - `+mbist_algo=2` (March C-)

Example:
```bash
vsim -c work.tb_top +firmware=firmware/firmware.hex +mbist_end=0000FFFC +mbist_algo=2 -do "run -all; quit -f"
```

## Where integration lives
- `tb/core/mm_ram.sv`: MBIST wrapper arbitrates access to RAM port B
- `tb/core/tb_top.sv`: power-on MBIST sequence + firmware load after PASS

