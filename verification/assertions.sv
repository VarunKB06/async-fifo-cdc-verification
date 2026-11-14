// Protocol / pointer / CDC checkers with EQUIVALENT intent in two implementations:
//   +define+USE_SVA  : native SystemVerilog Assertions (Riviera-PRO, XSim, Questa/Xcelium). Not Icarus.
//   (default)        : PROCEDURAL checkers (Icarus). These are NOT native SVA and are reported as such.
// Checks (W = write domain, R = read domain; names are identical in both modes' messages):
//   W1/R1  no accepted write while full / read while empty
//   W2/R2  pointer increments by exactly 1 after an accepted operation
//   W3/R3  pointer holds (binary and Gray) without an accepted operation
//   W4/R4  Gray == bin2gray(bin)
//   W5/R5  exactly one Gray bit changes after an accepted operation
//   W6/R6  reset behaviour: pointers 0 and flag at reset value while the domain reset is low
//   S1/S2  synchronizer pipeline: synced pointer == source pointer delayed by SYNC_STAGES destination edges
//   M1     memory write enable only with an accepted write (never while full)
// Internal DUT signals are used here (checkers only); the scoreboard never uses them.
module assertions #(
    parameter int AW          = 4,
    parameter int SYNC_STAGES = 2
) (
    input logic          wr_clk, rd_clk, wr_rst_n, rd_rst_n,
    input logic          wr_en, wr_ack, full, rd_en, rd_valid, empty,
    input logic [AW:0]   wbin, wgray, rbin, rgray,
    input logic [AW:0]   wgray_sync,     // write Gray pointer after synchronizer (read domain)
    input logic [AW:0]   rgray_sync,     // read Gray pointer after synchronizer (write domain)
    input logic          mem_we
);
    integer fail_count = 0;
    integer checks_run = 0;      // procedural mode only (native SVA has no portable evaluation counter)

    // number of clocks since the respective reset was released (used to skip the synchronizer warm-up)
    logic [7:0] w_rel = 0, r_rel = 0;
    always @(posedge wr_clk or negedge wr_rst_n) if (!wr_rst_n) w_rel <= 0; else if (w_rel != 8'hFF) w_rel <= w_rel + 1'b1;
    always @(posedge rd_clk or negedge rd_rst_n) if (!rd_rst_n) r_rel <= 0; else if (r_rel != 8'hFF) r_rel <= r_rel + 1'b1;
    wire sync_w_ok = wr_rst_n && rd_rst_n && (w_rel > SYNC_STAGES + 1) && (r_rel > SYNC_STAGES + 1);

`ifdef USE_SVA
    bit NATIVE_SVA = 1'b1;
    `define AFAIL(msg) else begin fail_count++; $error(msg); end

    // ---- write domain
    W1: assert property (@(posedge wr_clk) disable iff (!wr_rst_n) (wr_en && full) |-> !wr_ack) `AFAIL("W1 write accepted while full")
    W2: assert property (@(posedge wr_clk) disable iff (!wr_rst_n) wr_ack |=> (wbin == $past(wbin) + 1'b1)) `AFAIL("W2 wptr did not increment by 1")
    W3: assert property (@(posedge wr_clk) disable iff (!wr_rst_n) !wr_ack |=> ($stable(wbin) && $stable(wgray))) `AFAIL("W3 wptr/wgray moved without accepted write")
    W4: assert property (@(posedge wr_clk) disable iff (!wr_rst_n) wgray == ((wbin >> 1) ^ wbin)) `AFAIL("W4 wgray != bin2gray(wbin)")
    W5: assert property (@(posedge wr_clk) disable iff (!wr_rst_n) wr_ack |=> $onehot(wgray ^ $past(wgray))) `AFAIL("W5 wgray did not change exactly one bit")
    W6: assert property (@(posedge wr_clk) (!wr_rst_n && $past(!wr_rst_n)) |-> (wbin == '0 && wgray == '0 && full == 1'b0)) `AFAIL("W6 write-domain reset values")
    S1: assert property (@(posedge rd_clk) disable iff (!sync_w_ok) wgray_sync == $past(wgray, SYNC_STAGES)) `AFAIL("S1 wgray sync pipeline latency/value")
    M1: assert property (@(posedge wr_clk) disable iff (!wr_rst_n) mem_we |-> (wr_ack && !full)) `AFAIL("M1 memory write without accepted write")

    // ---- read domain
    R1: assert property (@(posedge rd_clk) disable iff (!rd_rst_n) (rd_en && empty) |-> !rd_valid) `AFAIL("R1 read accepted while empty")
    R2: assert property (@(posedge rd_clk) disable iff (!rd_rst_n) rd_valid |=> (rbin == $past(rbin) + 1'b1)) `AFAIL("R2 rptr did not increment by 1")
    R3: assert property (@(posedge rd_clk) disable iff (!rd_rst_n) !rd_valid |=> ($stable(rbin) && $stable(rgray))) `AFAIL("R3 rptr/rgray moved without accepted read")
    R4: assert property (@(posedge rd_clk) disable iff (!rd_rst_n) rgray == ((rbin >> 1) ^ rbin)) `AFAIL("R4 rgray != bin2gray(rbin)")
    R5: assert property (@(posedge rd_clk) disable iff (!rd_rst_n) rd_valid |=> $onehot(rgray ^ $past(rgray))) `AFAIL("R5 rgray did not change exactly one bit")
    R6: assert property (@(posedge rd_clk) (!rd_rst_n && $past(!rd_rst_n)) |-> (rbin == '0 && rgray == '0 && empty == 1'b1)) `AFAIL("R6 read-domain reset values")
    S2: assert property (@(posedge wr_clk) disable iff (!sync_w_ok) rgray_sync == $past(rgray, SYNC_STAGES)) `AFAIL("S2 rgray sync pipeline latency/value")
`else
    bit NATIVE_SVA = 1'b0;

    logic [AW:0] p_wbin, p_wgray, p_rbin, p_rgray, x;
    logic        p_wack = 0, p_rack = 0, p_wv = 0, p_rv = 0, p_wrst = 0, p_rrst = 0;
    // delay lines of the source Gray pointers, sampled at the DESTINATION clock (pre-edge values)
    logic [AW:0] wg_hist [1:SYNC_STAGES];
    logic [AW:0] rg_hist [1:SYNC_STAGES];

    task automatic bad(input [8*80-1:0] m);
        begin fail_count = fail_count + 1; $display("[CHECK FAIL] (procedural) t=%0t %0s", $time, m); end
    endtask

    function automatic logic onehot(input logic [AW:0] v);
        onehot = (v !== '0) && ((v & (v - 1'b1)) === '0);
    endfunction

    always @(posedge wr_clk) begin
        p_wrst <= !wr_rst_n;
        if (!wr_rst_n) begin
            p_wv <= 1'b0;
            if (p_wrst && !(wbin === '0 && wgray === '0 && full === 1'b0)) bad("W6 write-domain reset values");
        end else begin
            checks_run = checks_run + 1;
            if (wr_en && full && wr_ack)                 bad("W1 write accepted while full");
            if (wgray !== ((wbin >> 1) ^ wbin))          bad("W4 wgray != bin2gray(wbin)");
            if (mem_we && !(wr_ack && !full))            bad("M1 memory write without accepted write");
            if (p_wv) begin
                x = wgray ^ p_wgray;
                if (p_wack) begin
                    if (wbin !== p_wbin + 1'b1)          bad("W2 wptr did not increment by 1");
                    if (!onehot(x))                      bad("W5 wgray did not change exactly one bit");
                end else begin
                    if (wbin !== p_wbin || x !== '0)     bad("W3 wptr/wgray moved without accepted write");
                end
            end
            p_wbin <= wbin; p_wgray <= wgray; p_wack <= wr_ack; p_wv <= 1'b1;
        end
        // S2: rgray_sync (write domain) == rgray delayed SYNC_STAGES wr edges
        if (sync_w_ok) begin
            checks_run = checks_run + 1;
            if (rgray_sync !== rg_hist[SYNC_STAGES]) bad("S2 rgray sync pipeline latency/value");
        end
        rg_hist[1] <= rgray;
        for (int i = 2; i <= SYNC_STAGES; i++) rg_hist[i] <= rg_hist[i-1];
    end

    always @(posedge rd_clk) begin
        p_rrst <= !rd_rst_n;
        if (!rd_rst_n) begin
            p_rv <= 1'b0;
            if (p_rrst && !(rbin === '0 && rgray === '0 && empty === 1'b1)) bad("R6 read-domain reset values");
        end else begin
            checks_run = checks_run + 1;
            if (rd_en && empty && rd_valid)              bad("R1 read accepted while empty");
            if (rgray !== ((rbin >> 1) ^ rbin))          bad("R4 rgray != bin2gray(rbin)");
            if (p_rv) begin
                x = rgray ^ p_rgray;
                if (p_rack) begin
                    if (rbin !== p_rbin + 1'b1)          bad("R2 rptr did not increment by 1");
                    if (!onehot(x))                      bad("R5 rgray did not change exactly one bit");
                end else begin
                    if (rbin !== p_rbin || x !== '0)     bad("R3 rptr/rgray moved without accepted read");
                end
            end
            p_rbin <= rbin; p_rgray <= rgray; p_rack <= rd_valid; p_rv <= 1'b1;
        end
        if (sync_w_ok) begin
            checks_run = checks_run + 1;
            if (wgray_sync !== wg_hist[SYNC_STAGES]) bad("S1 wgray sync pipeline latency/value");
        end
        wg_hist[1] <= wgray;
        for (int i = 2; i <= SYNC_STAGES; i++) wg_hist[i] <= wg_hist[i-1];
    end
`endif
endmodule
