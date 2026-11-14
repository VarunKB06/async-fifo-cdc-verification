# Verification plan, matrix and status

**Execution status: no test in this repository has been executed by the author** (no simulator was available).
The "Result" column therefore says `not run` everywhere. Replace it with PASS/FAIL only from
`reports/run_stage*.log`.

## Environment
Procedural SystemVerilog testbench (`verification/tb_async_fifo.sv`), independent clocks (variable period, phase
shift), race-free reference scoreboard, native SVA (Riviera/XSim, `+define+USE_SVA`) or procedural checkers (Icarus,
*not* SVA), hand-written event/cross coverage. Random numbers: `$random(seed)`, `+seed=N` (printed in the summary).

## Scoreboard operation (verification/scoreboard.sv)
- Independent reference buffer of accepted writes; compare each accepted read with the oldest unread entry.
- Single writer per variable: the write monitor owns the buffer and `wr_cnt`/`wr_last_t`; the read monitor owns
  `rd_cnt`/`rd_last_t`. Causality uses time stamps: a monitor ignores a counterpart update that has the *current*
  time stamp, so coincident write/read edges are handled identically whatever the process order. No delays are used.
- Checks: `wr_ack`/`rd_valid` consistency, overflow, underflow/duplicate, data mismatch (corruption/loss/reorder are
  not distinguished), `full` required at max occupancy, `empty` required at zero occupancy, and a latency bound
  (a stale flag may last at most `SYNC_STAGES+1` destination edges). Missing data is caught by each test's drain check.
- Reset flushes the model; edges while either reset is low are ignored. The only second writer is that flush.
- DUT internal pointers are never used by the scoreboard.

## Assertions (verification/assertions.sv)
| ID | Property | Native SVA | Procedural (Icarus) |
|---|---|---|---|
| W1/R1 | no accepted write when full / read when empty | yes | yes |
| W2/R2 | pointer +1 after accepted op | yes | yes |
| W3/R3 | binary and Gray pointer hold without op | yes | yes |
| W4/R4 | Gray == bin2gray(bin) | yes | yes |
| W5/R5 | exactly one Gray bit changes on accepted op | yes | yes |
| W6/R6 | reset values while reset low | yes | yes |
| S1/S2 | synchronized pointer == source delayed `SYNC_STAGES` edges (after warm-up) | yes | yes (history registers) |
| M1 | memory write only with accepted write | yes | yes |
Native mode counts only failures; procedural mode also reports evaluations. Neither is formal verification.

## Coverage (verification/coverage.sv)
Event bins (38 for ADDR_WIDTH=4): status transitions, operations, occupancy, clock ratio, clock phase, pointer wrap,
per-bit Gray toggles (write/read), reset scenarios, recovery (first write/read after reset). Cross bins (32), reported
separately: X1 occupancy x write op (15), X2 clock ratio x op (6), X3 FIFO state at reset x activity (9),
X4 pointer wrap x concurrent op (2). Some cross bins may be unreachable (for example a blocked write at occupancy 0);
no bin is excluded automatically. Do not quote percentages until `reports/functional_coverage.txt` comes from a real run
and each MISS has been explained.

## Test matrix
| ID | Description | Status | File | Result |
|---|---|---|---|---|
| T1 | initial reset | implemented | tests/basic_tests.sv | not run |
| T2 | single write/read | implemented | basic_tests.sv | not run |
| T3 | sequential writes | implemented | basic_tests.sv | not run |
| T4 | sequential reads | implemented | basic_tests.sv | not run |
| T5 | full detection | implemented | basic_tests.sv | not run |
| T6 | empty detection | implemented | basic_tests.sv | not run |
| T7 | write while full | implemented | basic_tests.sv | not run |
| T8 | read while empty | implemented | basic_tests.sv | not run |
| T9 | recovery after full | implemented | basic_tests.sv | not run |
| T10 | recovery after empty | implemented | basic_tests.sv | not run |
| T11/T12 | pointer increment | via assertions W2/R2 (every test) | assertions.sv | not run |
| T13/T19 | wraparound | via T18 + wrap bins | boundary_tests.sv | not run |
| T14/T15 | Gray conversion / one-bit change | via W4/W5/R4/R5 | assertions.sv | not run |
| T16/T17 | max/min occupancy | implemented (T16) | boundary_tests.sv | not run |
| T18 | repeated fill/drain | implemented | boundary_tests.sv | not run |
| T20 | full/empty boundaries | implemented | boundary_tests.sv | not run |
| T21 | simultaneous r/w | implemented | cdc_tests.sv | not run |
| T22 | continuous r/w | covered by T21 | cdc_tests.sv | not run |
| T23/T24 | write faster / read faster | implemented | cdc_tests.sv | not run |
| T25/T36 | clock phase | implemented (T36) | cdc_tests.sv | not run |
| T26 | unequal periods | implemented | cdc_tests.sv | not run |
| T27/T28 | concurrency near full / empty | implemented | cdc_tests.sv | not run |
| T29 | repeated concurrent fill/drain | implemented | cdc_tests.sv | not run |
| T30 | long duration | = T56 | random_tests.sv | not run |
| T31 | write-pointer sync latency | implemented | cdc_tests.sv | not run |
| T32 | read-pointer sync latency | implemented | cdc_tests.sv | not run |
| T33 | latency over clock ratios | implemented | cdc_tests.sv | not run |
| T34 | pointer stability | via W3/R3 | assertions.sv | not run |
| T35/T37/T38 | clock ratios | implemented (T37, T38) | cdc_tests.sv | not run |
| T39 | wrap during CDC activity | via T21/T56 + X4 bins | - | not run |
| T40 | randomized CDC stress | = T54 | random_tests.sv | not run |
| T41 | initial reset | = T1 | basic_tests.sv | not run |
| T42/T43 | single-domain reset | **not supported** (system reset only) | - | n/a |
| T44/T45 | reset during write / read | implemented | reset_tests.sv | not run |
| T46 | reset during simultaneous ops | implemented | reset_tests.sv | not run |
| T47/T48 | reset full / empty | implemented | reset_tests.sv | not run |
| T49 | reset recovery | implemented | reset_tests.sv | not run |
| T50 | reset near clock edges | pending | - | - |
| T51 | random traffic | implemented | random_tests.sv | not run |
| T52/T53 | random write / read / simultaneous | folded into T51 | random_tests.sv | not run |
| T54 | random clock ratios | implemented | random_tests.sv | not run |
| T55 | random reset scenarios | implemented | random_tests.sv | not run |
| T56 | long random stress | implemented | random_tests.sv | not run |
| T57 | random boundary conditions | implemented | random_tests.sv | not run |
| T58 | random fill/drain cycles | implemented | random_tests.sv | not run |
| - | negative tests / bug injection | pending | - | - |
