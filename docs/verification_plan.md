# Verification plan, matrix and status

**Execution status:** all 41 tests passed with seeds 1, 2 and 3 in GitHub Actions (Icarus Verilog), logs in
`reports/ci_logs/`, and 38/38 in the author's local Vivado 2026.1 XSim run. Native-SVA mode was not run. Rows that say
"via ..." are checked continuously by the procedural checkers (0 failures); rows marked pending were not implemented.

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
| T1 | initial reset | implemented | tests/basic_tests.sv | PASS (CI seeds 1-3) |
| T2 | single write/read | implemented | basic_tests.sv | PASS (CI seeds 1-3) |
| T3 | sequential writes | implemented | basic_tests.sv | PASS (CI seeds 1-3) |
| T4 | sequential reads | implemented | basic_tests.sv | PASS (CI seeds 1-3) |
| T5 | full detection | implemented | basic_tests.sv | PASS (CI seeds 1-3) |
| T6 | empty detection | implemented | basic_tests.sv | PASS (CI seeds 1-3) |
| T7 | write while full | implemented | basic_tests.sv | PASS (CI seeds 1-3) |
| T8 | read while empty | implemented | basic_tests.sv | PASS (CI seeds 1-3) |
| T9 | recovery after full | implemented | basic_tests.sv | PASS (CI seeds 1-3) |
| T10 | recovery after empty | implemented | basic_tests.sv | PASS (CI seeds 1-3) |
| T11/T12 | pointer increment | via assertions W2/R2 (every test) | assertions.sv | checked, 0 failures (CI) |
| T13/T19 | wraparound | via T18 + wrap bins | boundary_tests.sv | checked, 0 failures (CI) |
| T14/T15 | Gray conversion / one-bit change | via W4/W5/R4/R5 | assertions.sv | checked, 0 failures (CI) |
| T16/T17 | max/min occupancy | implemented (T16) | boundary_tests.sv | PASS (CI seeds 1-3) |
| T18 | repeated fill/drain | implemented | boundary_tests.sv | PASS (CI seeds 1-3) |
| T20 | full/empty boundaries | implemented | boundary_tests.sv | PASS (CI seeds 1-3) |
| T21 | simultaneous r/w | implemented | cdc_tests.sv | PASS (CI seeds 1-3) |
| T22 | continuous r/w | covered by T21 | cdc_tests.sv | PASS (CI seeds 1-3) |
| T23/T24 | write faster / read faster | implemented | cdc_tests.sv | PASS (CI seeds 1-3) |
| T25/T36 | clock phase | implemented (T36) | cdc_tests.sv | PASS (CI seeds 1-3) |
| T26 | unequal periods | implemented | cdc_tests.sv | PASS (CI seeds 1-3) |
| T27/T28 | concurrency near full / empty | implemented | cdc_tests.sv | PASS (CI seeds 1-3) |
| T29 | repeated concurrent fill/drain | implemented | cdc_tests.sv | PASS (CI seeds 1-3) |
| T30 | long duration | = T56 | random_tests.sv | PASS (CI seeds 1-3) |
| T31 | write-pointer sync latency | implemented | cdc_tests.sv | PASS (CI seeds 1-3) |
| T32 | read-pointer sync latency | implemented | cdc_tests.sv | PASS (CI seeds 1-3) |
| T33 | latency over clock ratios | implemented | cdc_tests.sv | PASS (CI seeds 1-3) |
| T34 | pointer stability | via W3/R3 | assertions.sv | checked, 0 failures (CI) |
| T35/T37/T38 | clock ratios | implemented (T37, T38) | cdc_tests.sv | PASS (CI seeds 1-3) |
| T39 | wrap during CDC activity | via T21/T56 + X4 bins | - | checked, 0 failures (CI) |
| T40 | randomized CDC stress | = T54 | random_tests.sv | PASS (CI seeds 1-3) |
| T41 | initial reset | = T1 | basic_tests.sv | PASS (CI seeds 1-3) |
| T42/T43 | single-domain reset | **not supported** (system reset only) | - | n/a |
| T44/T45 | reset during write / read | implemented | reset_tests.sv | PASS (CI seeds 1-3) |
| T46 | reset during simultaneous ops | implemented | reset_tests.sv | PASS (CI seeds 1-3) |
| T47/T48 | reset full / empty | implemented | reset_tests.sv | PASS (CI seeds 1-3) |
| T49 | reset recovery | implemented | reset_tests.sv | PASS (CI seeds 1-3) |
| T50 | reset near clock edges | pending | - | - |
| T51 | random traffic | implemented | random_tests.sv | PASS (CI seeds 1-3) |
| T52/T53 | random write / read / simultaneous | folded into T51 | random_tests.sv | PASS (CI seeds 1-3) |
| T54 | random clock ratios | implemented | random_tests.sv | PASS (CI seeds 1-3) |
| T55 | random reset scenarios | implemented | random_tests.sv | PASS (CI seeds 1-3) |
| T56 | long random stress | implemented | random_tests.sv | PASS (CI seeds 1-3) |
| T57 | random boundary conditions | implemented | random_tests.sv | PASS (CI seeds 1-3) |
| T58 | random fill/drain cycles | implemented | random_tests.sv | PASS (CI seeds 1-3) |
| T59 | blocked write with stale `full`, occupancy 0 / low (extra, closes cross bins) | implemented | cdc_tests.sv | PASS (CI seeds 1-3) |
| T60 | reset at empty, write+read active (extra, closes cross bins) | implemented | reset_tests.sv | PASS (CI seeds 1-3) |
| T61 | reset at full, write+read active (extra, closes cross bins) | implemented | reset_tests.sv | PASS (CI seeds 1-3) |
| - | negative tests / bug injection | pending | - | - |

## Cross-coverage analysis (41-test CI runs, seeds 1-3: CROSS 29 / 32 raw, 29 / 29 reachable)
The 38-test baseline had 23 / 32. The classification below was made by reasoning about the design and is now confirmed
for the reachable bins by `HIT` in all three seed logs.
| Bin | Class | Result |
|---|---|---|
| X1 occupancy=0 x write+concurrent read | unreachable: a read cannot be accepted at occupancy 0 | `EXCL` |
| X1 occupancy=max x write-only | unreachable: a write cannot be accepted while `full` is set at max occupancy | `EXCL` |
| X1 occupancy=max x write+read | unreachable: same reason | `EXCL` |
| X1 occupancy=0 x blocked write | reachable: stale `full` while a fast read clock drains the FIFO (T59, 16 reads) | HIT |
| X1 occupancy=low x blocked write | reachable: same effect, drain stopped at occupancy 2 (T59, 14 reads) | HIT |
| X3 reset at empty x write active / read active | reachable (T60) | HIT |
| X3 reset at full x write active / read active | reachable (T61) | HIT |
The coverage report prints the raw total (29 / 32) and the reachable total (29 / 29, excluded bins marked `EXCL`).
Exclusions are justified by the reasons above; they do not apply to a faulty DUT, where such a bin being hit would itself
indicate a bug.
