# Async_FIFO_CDC: parameterizable asynchronous FIFO with SystemVerilog verification

Dual-clock FIFO (Gray-coded pointers, 2-flop synchronizers) plus a procedural SystemVerilog verification
environment: independent reference-queue scoreboard, pointer/protocol assertions, directed + randomized tests,
functional event-bin coverage and a scripted regression.

> **Status.** Functionally simulated by the author in **Vivado 2026.1 XSim** (results below, reported from the
> author's local run; the Vivado log is not committed yet). **GitHub Actions status: pending.** The CI workflow was
> rewritten for Icarus Verilog but its first run has not been confirmed. Do not treat the numbers below as
> reproduced by CI until the Actions badge/run is green and the uploaded logs show them.

### Reference result (author's local Vivado 2026.1 XSim run, assertions are procedural checkers, not native SVA)
| Item | Result |
|---|---|
| Tests | 38 / 38 passed, 0 failed |
| Scoreboard errors / assertion failures | 0 / 0 |
| Total checks | 112,332 (testbench 260, scoreboard 112,072) |
| Accepted writes / reads compared | 20,159 / 20,035 |
| Functional EVENT bins | 39 / 39 |
| Functional CROSS bins | 25 / 32 (unreached bins not yet analysed/excluded) |
| Procedural checker evaluations | 183,527 |

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
(`+define+USE_SVA`). Record the simulator version (the log's first line has it for Icarus).

## Continuous integration (GitHub Actions)
Workflow: `.github/workflows/regression.yml` (Icarus Verilog on `ubuntu-24.04`).
- **Triggers:** every push / pull request to `main` or `master`, and manually (Actions tab -> *Async FIFO CDC
  regression* -> *Run workflow*).
- **Job `regression`:** matrix over seeds 1, 2, 3. Each seed compiles with `iverilog -g2012`, runs `tb_async_fifo`
  with all stages, and fails if the compiler or simulator returns non-zero, the log has no `FINAL: PASS`, any
  failed test / scoreboard error / assertion failure is reported, or the requested seed is missing from the log.
  Artifacts: `sim-logs-seed-1|2|3` (compile + simulation logs, model sanity log).
- **Job `waveform`:** runs stage 1 with `+vcd` and uploads `waveform-stage1-seed1` (`.vcd`, open with GTKWave).
- The workflow calls the tools directly (no shell-script permission dependence). Logs/waveforms are uploaded even when
  a step fails (`if: always()`).
- The testbench writes a VCD only when `+vcd` is given, so Vivado/XSim runs no longer try to open a relative path.
- Download artifacts from the run summary page (bottom, *Artifacts*).

## Implemented vs verified
| Item | Written | Run / passing |
|---|---|---|
| RTL (8 files; `gray_decoder` omitted, not needed) | yes | no |
| Scoreboard, assertions, coverage bins | yes | no |
| Tests (matrix in docs/verification_plan.md) | yes | no |
| Synchronizer-latency assertions/tests, cross coverage, near-boundary tests | yes | no |
| T50, negative tests, bug injection | no | no |
| GitHub Actions workflow | yes (untested) | no |
| UVM, formal, static CDC, synthesis | no | no |

## Limitations
- Single-domain reset is unsupported (system reset only).
- Simulation cannot prove metastability safety; no static CDC or formal analysis was done.
- Scoreboard cannot tell loss from reordering from corruption; it reports a data mismatch.
- `dout` uses an asynchronous memory read (LUT-RAM/register-file style); no block-RAM mapping (see architecture.md).
- Reset is applied at fixed offsets, not randomly near clock edges (T50 pending).
