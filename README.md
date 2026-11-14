# Async_FIFO_CDC: parameterizable asynchronous FIFO with SystemVerilog verification

Dual-clock FIFO (Gray-coded pointers, 2-flop synchronizers) plus a procedural SystemVerilog verification
environment: independent reference-queue scoreboard, pointer/protocol assertions, directed + randomized tests,
functional event-bin coverage and a scripted regression.

> **Status: simulated and passing.** The full regression (38 tests) passes in **GitHub Actions with Icarus Verilog**
> for seeds 1, 2 and 3, and the author's local **Vivado 2026.1 XSim** run reported the same 38/38. Assertions are
> procedural checkers, not native SVA. Logs are in `reports/ci_logs/`; the waveform views below are drawn from the CI VCD.

## Results

### GitHub Actions (Icarus Verilog, `+STAGE=0`, all 38 tests)
| Item | seed 1 | seed 2 | seed 3 |
|---|---|---|---|
| Tests passed / failed | 38 / 0 | 38 / 0 | 38 / 0 |
| Scoreboard errors | 0 | 0 | 0 |
| Assertion (procedural check) failures | 0 | 0 | 0 |
| Total checks | 112,380 | 117,627 | 111,670 |
| Writes / reads compared | 20,008 / 19,867 | 20,707 / 20,552 | 20,054 / 19,912 |
| Functional EVENT bins | 39 / 39 | 39 / 39 | 39 / 39 |
| Functional CROSS bins | 23 / 32 | 23 / 32 | 23 / 32 |
| Final | PASS | PASS | PASS |

Source: `reports/ci_logs/sim_seed{1,2,3}.log`; seed-1 extracts in `reports/simulation_summary.txt`,
`reports/assertion_summary.txt` (183,960 procedural check evaluations) and `reports/functional_coverage.txt`.

### Author's local Vivado 2026.1 XSim run (earlier reference, log not committed)
38 / 38 tests, 0 scoreboard errors, 0 assertion failures, 112,332 checks (260 testbench + 112,072 scoreboard),
20,159 writes / 20,035 reads compared, EVENT 39 / 39, CROSS 25 / 32, 183,527 procedural check evaluations.
Counts differ slightly from CI because random streams differ between simulators.

### Coverage notes
EVENT bins are 100% covered. CROSS coverage is 23 / 32; the 9 missed bins (all seeds, listed in
`reports/functional_coverage.txt`) are classified in [docs/verification_plan.md](docs/verification_plan.md)
(4 unreachable by construction, 5 reachable but not yet hit). Event-bin coverage is hand-written functional coverage,
not RTL code coverage and not formal CDC proof.

### Waveforms (stage 1, seed 1, from the CI VCD `waveforms/tb_async_fifo_stage1_seed1.vcd`)
These images are rendered from the VCD by `scripts/vcd_to_png.py` (matplotlib), not GTKWave screenshots; open the VCD
in GTKWave to inspect any signal.

![T2 single write/read](waveforms/t2_single_write_read.png)
*T2: one write is accepted; `empty` de-asserts only after the write pointer crosses the synchronizer; the read pops the word and `empty` returns.*

![T5 fill to full](waveforms/t5_fill_to_full.png)
*T5: sixteen consecutive writes raise occupancy 1 to 16; `full` asserts with the 16th write and `wr_ack` stops.*

![T9 recovery after full](waveforms/t9_full_recovery.png)
*T9: reads reduce occupancy; `full` stays high for a few write-clock edges (read pointer in the synchronizer) before clearing.*

## Why an asynchronous FIFO
A producer and a consumer on unrelated clocks cannot share a binary counter safely. Only Gray-coded pointers
(one bit changes per step) go through synchronizers, so a sampled pointer is always a valid old-or-new value.

## Layout
`rtl/` design, `verification/` testbench, scoreboard, assertions, coverage and `tests/`, `scripts/` runners,
`docs/` specification and plan, `reports/` and `waveforms/` (filled by real runs).
Design details, interface timing (combinational first-word-fall-through `dout`), flag equations and the reset
protocol are in [docs/architecture.md](docs/architecture.md); the test list and status in
[docs/verification_plan.md](docs/verification_plan.md).

## Run
```
./scripts/run_stage1.sh      # basic tests
./scripts/run_stage2.sh      # boundary + clock ratio/phase tests
./scripts/run_stage3.sh      # reset + randomized tests
./scripts/run_all.sh         # stages 1,2,3 + combined run; writes reports/*.txt; nonzero exit on ANY failure
SEED=7 WAVES=1 bash scripts/run_all.sh iverilog      # or: ./scripts/run_all.sh riviera  (native SVA)
```
Run from the repo root. Icarus Verilog needs `-g2012` support for queues and SystemVerilog tasks (version 12
recommended). With Icarus the assertions are **procedural checkers, not native SVA**; Riviera-PRO/XSim uses real SVA
(`+define+USE_SVA`). The CI log step "Show simulator version" records the Icarus version.

## Continuous integration (GitHub Actions)
Workflow: `.github/workflows/regression.yml` (Icarus Verilog on `ubuntu-24.04`).
- **Triggers:** every push / pull request to `main` or `master`, and manually (Actions tab -> *Async FIFO CDC
  regression* -> *Run workflow*).
- **Job `regression`:** matrix over seeds 1, 2, 3. Each seed compiles with `iverilog -g2012`, runs `tb_async_fifo`
  with all stages, and fails if the compiler or simulator returns non-zero, the log has no `FINAL: PASS`, any
  failed test / scoreboard error / assertion failure is reported, or the requested seed is missing from the log.
  Artifacts: `sim-logs-seed-1|2|3` (compile + simulation logs, model sanity log).
- **Job `waveform`:** runs stage 1 with `+vcd` and uploads `waveform-stage1-seed1` (`.vcd`, open with GTKWave).
  To refresh the images: `python3 scripts/vcd_to_png.py waveforms/tb_async_fifo_stage1_seed1.vcd waveforms/`.
- The workflow calls the tools directly (no shell-script permission dependence). Logs/waveforms are uploaded even when
  a step fails (`if: always()`).
- The testbench writes a VCD only when `+vcd` is given, so Vivado/XSim runs no longer try to open a relative path.
- Download artifacts from the run summary page (bottom, *Artifacts*).

## Implemented vs verified
| Item | Written | Run / result |
|---|---|---|
| RTL (7 modules; `gray_decoder` omitted, not needed) | yes | simulated: Vivado XSim, Icarus (CI) |
| Scoreboard, procedural checkers, coverage bins | yes | 0 errors, 0 failures; EVENT 39/39, CROSS 23/32 (CI) |
| 38 tests (matrix in docs/verification_plan.md) | yes | 38/38 PASS, seeds 1-3 (CI) |
| Synchronizer-latency checks/tests (T31-T33) | yes | PASS |
| GitHub Actions workflow | yes | green for seeds 1, 2, 3 and waveform job |
| T50, negative tests, bug injection | no | pending |
| Native SVA mode (`+define+USE_SVA`) | yes | not run |
| UVM, formal, static CDC, synthesis | no | not done |

## Limitations
- Single-domain reset is unsupported (system reset only).
- Simulation cannot prove metastability safety; no static CDC or formal analysis was done.
- Scoreboard cannot tell loss from reordering from corruption; it reports a data mismatch.
- `dout` uses an asynchronous memory read (LUT-RAM/register-file style); no block-RAM mapping (see architecture.md).
- Reset is applied at fixed offsets, not randomly near clock edges (T50 pending).
