// Independent reference model, race-free across two unrelated clocks.
//
// Why the old version raced: one SystemVerilog queue was pushed from the wr_clk process and popped from the
// rd_clk process; when both clocks have an edge in the same time step the order of the two processes is
// undefined, so queue size() / pop results could differ between simulators or runs.
//
// New structure (single writer per variable, causality decided by TIME STAMPS, no delays):
//   * ref_data[] / wr_cnt / wr_last_t  are written ONLY by the write-clock monitor.
//   * rd_cnt / rd_last_t               are written ONLY by the read-clock monitor.
//   * Each monitor reads the other side's counter but discounts an update that carries the CURRENT time stamp.
//     A write and a read that happen in the same time step can never be causally related in a FIFO with
//     synchronizers, so "events at the same time are invisible to each other" is both correct and deterministic,
//     whichever process the simulator runs first.
//   * The only shared writer is the reset flush (see below).
// Both monitors sample DUT outputs at their own clock edge in the active region; DUT outputs only change in
// the NBA region, so samples are pre-edge values (same as the flops see).
//
// Reset: asserting either reset flushes the model (counters := 0). Edges seen while either reset is low are
// ignored. Flushing and a monitor can coincide only if reset asserts in the same ps as a clock edge; both
// orderings end with an empty model.
//
// Flag checks (CDC-safe; synchronizer latency makes flags pessimistic, never optimistic):
//   full  MUST be 1 when true occupancy == DEPTH;   empty MUST be 1 when true occupancy == 0.
//   full may remain 1 / empty may remain 1 while the opposite pointer is in flight, but only for
//   SYNC_STAGES+1 destination-clock edges (verified with docs/model/fifo_model.py); longer is an error
//   ("latency bound" check).
module scoreboard #(
    parameter int DW          = 8,
    parameter int DEPTH       = 16,
    parameter int SYNC_STAGES = 2
) (
    input  logic          wr_clk, rd_clk, wr_rst_n, rd_rst_n,
    input  logic          wr_en,  wr_ack, full,
    input  logic [DW-1:0] din,
    input  logic          rd_en,  rd_valid, empty,
    input  logic [DW-1:0] dout,
    output logic [31:0]   occ
);
    localparam int RB        = 4 * DEPTH;          // circular reference buffer (occupancy never exceeds DEPTH)
    localparam int LAT_LIMIT = SYNC_STAGES + 1;    // max legal destination edges with a stale pessimistic flag

    logic [DW-1:0] ref_data [0:RB-1];
    integer        wr_cnt = 0, rd_cnt = 0;         // accepted writes / reads since last reset
    time           wr_last_t = 0, rd_last_t = 0;   // time of most recent accepted write / read
    integer        full_stuck = 0, empty_stuck = 0;
    integer        errors = 0, checks = 0, writes = 0, reads = 0;
    logic [DW-1:0] exp_data;

    wire active = wr_rst_n & rd_rst_n;
    assign occ  = wr_cnt - rd_cnt;                 // monitors' view; read it away from clock edges

    task automatic err(input [8*80-1:0] m);
        begin errors = errors + 1; $display("[SB ERROR] t=%0t %0s", $time, m); end
    endtask

    // ---------------- reset flush
    always @(negedge wr_rst_n or negedge rd_rst_n) begin
        wr_cnt = 0; rd_cnt = 0; wr_last_t = 0; rd_last_t = 0; full_stuck = 0; empty_stuck = 0;
    end

    // ---------------- write-clock monitor
    integer occ_w, rd_before;
    always @(posedge wr_clk) if (active) begin
        checks = checks + 1;
        if (wr_ack !== (wr_en & ~full)) err("wr_ack != wr_en & ~full");
        rd_before = rd_cnt - ((rd_cnt > 0 && rd_last_t == $time) ? 1 : 0);   // reads strictly before this edge
        occ_w     = wr_cnt - rd_before;
        if (occ_w >= DEPTH && full !== 1'b1) err("full not asserted at max occupancy");
        if (full === 1'b1 && occ_w < DEPTH) full_stuck = full_stuck + 1; else full_stuck = 0;
        if (full_stuck > LAT_LIMIT) err("full stuck high longer than synchronizer latency");
        if (wr_ack === 1'b1) begin
            if (occ_w >= DEPTH) err("write accepted while FIFO truly full (overflow / data loss)");
            else begin
                ref_data[wr_cnt % RB] = din;
                wr_cnt = wr_cnt + 1; wr_last_t = $time; writes = writes + 1;
            end
        end
    end

    // ---------------- read-clock monitor
    integer avail, wr_before;
    always @(posedge rd_clk) if (active) begin
        checks = checks + 1;
        if (rd_valid !== (rd_en & ~empty)) err("rd_valid != rd_en & ~empty");
        wr_before = wr_cnt - ((wr_cnt > 0 && wr_last_t == $time) ? 1 : 0);   // writes strictly before this edge
        avail     = wr_before - rd_cnt;
        if (avail <= 0 && empty !== 1'b1) err("empty not asserted at zero occupancy");
        if (empty === 1'b1 && avail > 0) empty_stuck = empty_stuck + 1; else empty_stuck = 0;
        if (empty_stuck > LAT_LIMIT) err("empty stuck high longer than synchronizer latency");
        if (rd_valid === 1'b1) begin
            if (avail <= 0) err("read accepted with no data (underflow / duplicate)");
            else begin
                exp_data = ref_data[rd_cnt % RB];
                rd_cnt = rd_cnt + 1; rd_last_t = $time; reads = reads + 1; checks = checks + 1;
                if (dout !== exp_data) begin
                    err("data mismatch (corruption / loss / reorder)");
                    $display("          got 0x%0h expected 0x%0h", dout, exp_data);
                end
            end
        end
    end
endmodule
