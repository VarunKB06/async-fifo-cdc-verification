# Change log

## Cross-bin closure (written, not yet run)
- Added directed tests T59 (blocked write with stale `full` at occupancy 0 and 2, `cdc_tests.sv`), T60 (reset at
  empty, write+read active) and T61 (reset at full, write+read active) in `reset_tests.sv`.
- `coverage.sv`: the 3 unreachable X1 bins are marked `EXCL` and a reachable total (x / 29) is reported next to the raw
  total (x / 32); `tb_async_fifo.sv` prints both in the summary. Shortened one check message (>48 characters).
- README / `docs/verification_plan.md` updated; results are intentionally NOT updated until the next CI run.

## Documentation update (final README)
- README: removed script-rendered images, added GTKWave screenshots, layout tree, verification architecture,
  test summary, future work; scripts shown with `bash`.

## Results and documentation update
- CI green: 38/38 tests pass for seeds 1, 2, 3 (Icarus Verilog); results, per-seed logs, coverage and assertion
  summaries committed under `reports/`; stage-1 VCD committed under `waveforms/`.
- Added three GTKWave screenshots of the CI VCD under `waveforms/` and referenced them in the README.
- README and `docs/verification_plan.md` updated with real results, cross-bin analysis and a status table.
- `.gitignore`: committed `waveforms/*.vcd` allowed.

## CI fix 3 (first Icarus simulation: 36/38 tests failed)
- Root cause: `scoreboard.sv` (and the other verification modules) had no `timescale`. Icarus compiled them before the
  testbench's `timescale 1ps/1ps`, so they used the default 1 s unit and `$time` was always 0. The scoreboard's
  same-time-stamp causality rule (`wr_last_t == $time`) was therefore always true and mis-counted occupancy. Vivado
  inherited the testbench timescale, which is why it passed. Fixed by adding `timescale 1ps/1ps` to
  `scoreboard.sv`, `assertions.sv`, `coverage.sv`.
- `tb_async_fifo.sv`: summary printed `seed` after `$random(seed)` had modified it; it now prints the requested seed.

## CI fix 2 (Icarus compile errors from the first CI run)
- `coverage.sv`: the `` `PR `` report macro was rejected by Icarus (syntax errors at lines 150-164 in every job);
  replaced by a task `pr()`. Removed the string-returning function `occ_name` (cross X1 now printed explicitly).
- `scoreboard.sv`, `assertions.sv`: message arguments are packed vectors instead of `string`.
- `scoreboard.sv`, `synchronizer.sv`: unpacked arrays use explicit `[0:N-1]` bounds.
- Behaviour unchanged; Vivado baseline should be re-run once to confirm.

## CI fix (workflow rewrite)
- Replaced the workflow: no dependence on executable bits (the old `./scripts/check_model.sh` call failed with exit
  126 because the file was committed without +x). Python model is now run as `python3 docs/model/fifo_model.py`.
- Direct `iverilog -g2012 -s tb_async_fifo` compile and `vvp` run per seed (1, 2, 3), result checks, logs uploaded
  with `if: always()`, separate VCD job (stage 1, seed 1).
- `tb_async_fifo.sv`: VCD dump only with `+vcd` (was unconditional relative path; XSim could not open it).
  `+nowave` removed. No change to checks, scoreboard, assertions or coverage.
- `scripts/run.sh`: `WAVES=1` now passes `+vcd` (default off).
- Added `.gitattributes` (LF endings for `.sh/.sv/.yml/.py`); the old testbench file had CRLF line endings.
- (Status at the time of this entry: CI result not yet confirmed; see the entries above.)

## Audit pass 1 (written before any simulator was available)

No simulator was available, so **nothing below was compiled or simulated**. The only executed artefact is the Python
algorithm model (`docs/model/fifo_model.py`, 400 random configurations: 0 errors, max stale-flag run = SYNC_STAGES+1).

## Fixed
- **Scoreboard race (priority 1).** Shared queue pushed/popped from two clock processes replaced by single-writer
  counters/buffer with time-stamp causality; deterministic for coincident edges, no delays. Occupancy is derived from
  the two counters. Flag checks now use occupancy "strictly before this edge", and a latency bound check was added.
- **RTL parameter checks.** `ADDR_WIDTH<2`, `SYNC_STAGES<2`, `DATA_WIDTH<1` stop the simulation (async_fifo,
  synchronizer, full_empty_logic). Synthesis implication of the asynchronous memory read documented.
- **Assertions.** Added hold checks (binary + Gray), exact one-bit Gray change, reset-value checks, synchronizer
  pipeline-latency checks and memory-write protection; procedural fallback rewritten with the same IDs/intent
  (W1-W6, R1-R6, S1-S2, M1) and labelled "procedural".
- **Coverage.** Single-writer vectors (no shared read-modify-write), recovery bins, per-bit Gray toggle bins, four
  cross groups reported separately from event bins.
- **Tests.** Added T27-T29, T31-T33, T44, T45, T57, T58.
- **Scripts.** Compile failure, simulator exit status, missing FINAL line, watchdog and missing simulator all give a
  nonzero exit; `run_all.sh` runs stages 1,2,3 and the combined run and fails if any fails; `WAVES=0` option;
  workflow runs 3 seeds and fails on any failure.
- **Docs.** README, architecture, verification plan (matrix) updated.

## Still pending
Everything that requires a simulator: compile fixes, real results, real coverage, waveform evidence. Also: T50,
negative tests/bug injection, formal/static CDC, UVM, synthesis. The reset-assertion-on-clock-edge case (same ps)
is not excluded in the testbench. The `$error`-then-`$finish` parameter checks and several SystemVerilog constructs
(queues removed, but `string` tasks, `task automatic`, `for (int ...)`) need a recent Icarus (12+) or Riviera/XSim.
