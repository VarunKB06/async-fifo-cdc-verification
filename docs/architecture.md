# Architecture and design specification

## Block diagram
```
 wr_clk domain                                          rd_clk domain
 wr_en,din --> [write_pointer] --wgray--> synchronizer ------------> wgray_sync
                 wbin/waddr   ^                                          |
                     |        +<-- rgray_sync <-- synchronizer <-- rgray (read_pointer)
          [fifo_memory] <-- waddr                       raddr --> [fifo_memory] --> dout
 full  <-- reg <-- [full_empty_logic] --> reg --> empty
```
Both pointers are ADDR_WIDTH+1 bits (extra MSB distinguishes full from empty). Only Gray-coded pointers cross
clock domains, through `SYNC_STAGES`-flop synchronizers (default 2).

## Interface and timing (decided before implementation)
| Signal | Meaning |
|---|---|
| `wr_ack = wr_en & ~full` | combinational; write is stored at the next `wr_clk` edge |
| `rd_valid = rd_en & ~empty` | combinational; read is accepted at the next `rd_clk` edge |
| `dout` | **combinational** `mem[read pointer]` (first-word fall-through). It holds the word being popped in the same cycle as `rd_valid`. Don't-care when empty. |
| `full` / `empty` | registered in their own clock domain, computed from *next* pointers. `empty` resets to 1, `full` to 0. |

Supported parameters (checked at time 0; violation prints an error and stops the simulation):
`DATA_WIDTH` >= 1 (default 8), `ADDR_WIDTH` >= 2 (default 4, depth = 2**ADDR_WIDTH), `SYNC_STAGES` >= 2 (default 2).
`ADDR_WIDTH >= 2` is required because full detection inverts the two MSBs of the synchronized read Gray pointer.

## Pointer and flag equations
- `gray = (bin >> 1) ^ bin`; next pointers use the accepted write/read (`wr_ack` / `rd_valid`).
- `full_next  = (wgray_next == {~rgray_sync[N:N-1], rgray_sync[N-2:0]})`, N = ADDR_WIDTH
- `empty_next = (rgray_next == wgray_sync)`
- Synchronized pointers are stale by 2-3 destination clocks, so flags are *pessimistic*: `full` may clear late and
  `empty` may clear late, but they can never be falsely de-asserted. The scoreboard checks exactly this.

## Reset strategy and assumptions
- `wr_rst_n` and `rd_rst_n` assert asynchronously and are expected to be **released synchronously to their own clock**
  (use an external reset synchronizer in a real SoC; the testbench does this explicitly).
- **Supported:** system reset, i.e. both domains reset together, held for several cycles of both clocks, with no
  traffic across the release.
- **Not supported / not verified:** resetting only one domain while the other keeps operating. It can leave the
  pointers inconsistent. Tests T42/T43 are therefore intentionally not implemented.

## What simulation does not establish
RTL simulation cannot show metastability safety; two-flop synchronizers only reduce the risk. Gray-code checks do not
replace static CDC analysis. Functional event bins are not code coverage. Assertions are not formal proof. Nothing here
shows timing closure. The `ASYNC_REG`/`keep` attributes express the intent that synchronizer flops must not be
optimized away; this has not been checked in a synthesis tool.

## Synchronizer latency (expected, model-checked)
A pointer update is seen by the other domain after `SYNC_STAGES` destination edges, and the flag register updates one
edge later, so a stale flag can persist for at most `SYNC_STAGES+1` destination edges (3 for the default). The
scoreboard and tests T31-T33 check this bound. The bound was confirmed on a Python model of the same equations
(`docs/model/fifo_model.py`, 400 random configurations, 0 errors); that model is **not** an RTL simulation.

## Synthesis implications
- `fifo_memory` reads asynchronously (`dout = mem[raddr]`) to give first-word-fall-through output. This maps to
  LUT-RAM / register-file / flop arrays. It cannot infer a synchronous-read block RAM; a BRAM version needs a
  registered-read interface or an extra output register (not implemented).
- The `ASYNC_REG`/`keep` attributes on the synchronizer flops state the intent that they must not be merged or
  retimed. Whether a given tool honours them was not checked. Static CDC analysis was not run.
- The memory content is not reset; `dout` is only meaningful while `rd_valid` is high.
