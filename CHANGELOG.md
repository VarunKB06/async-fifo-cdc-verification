# Change log (audit pass 1)

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
