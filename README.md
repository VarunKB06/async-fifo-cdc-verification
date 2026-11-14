# Async_FIFO_CDC: parameterizable asynchronous FIFO with SystemVerilog verification

Dual-clock FIFO (Gray-coded pointers, 2-flop synchronizers) plus a procedural SystemVerilog verification
environment: independent reference-queue scoreboard, pointer/protocol assertions, directed + randomized tests,
functional event-bin coverage and a scripted regression.

> **Status: audited draft, still never simulated.** The code was written and reviewed without access to a simulator.
> Nothing here counts as passing until you run `scripts/run_all.sh` and commit the generated `reports/` files.
> No results, coverage numbers or waveform screenshots are included, on purpose. See `CHANGELOG.md` for the audit.
> The only executed check is a Python model of the algorithm (`scripts/check_model.sh`), which is not an RTL run.

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
SEED=7 WAVES=0 ./scripts/run_all.sh iverilog      # or: ./scripts/run_all.sh riviera  (native SVA)
```
Run from the repo root. Icarus Verilog needs `-g2012` support for queues and SystemVerilog tasks (version 12
recommended). With Icarus the assertions are **procedural checkers, not native SVA**; Riviera-PRO/XSim uses real SVA
(`+define+USE_SVA`). Record the simulator version (the log's first line has it for Icarus).

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
