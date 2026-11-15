`timescale 1ps/1ps
// Hand-written functional coverage collector (plain Verilog/SV, works in Icarus).
//   * EVENT bins : single-condition events (status, ops, occupancy, ratio/phase, wrap, Gray bit toggles, reset).
//   * CROSS bins : combinations of those events. Reported SEPARATELY from event bins.
// This is NOT RTL code coverage and NOT covergroup (native) coverage.
// Race-freedom: every bit vector is written by exactly one process (wr monitor, rd monitor or reset monitor)
// and the totals are the OR of the vectors, so processes never read-modify-write the same variable.
module coverage #(parameter int AW = 4) (
    input logic        wr_clk, rd_clk, wr_rst_n, rd_rst_n,
    input logic        wr_en, wr_ack, full, rd_en, rd_valid, empty,
    input logic [AW:0] wbin, wgray, rbin, rgray,
    input logic [31:0] occ,
    input logic [31:0] wr_half, rd_half, phase_shift
);
    localparam int DEPTH = 1 << AW;
    localparam int NB = 29;
    localparam int B_FULL=0, B_EMPTY=1, B_E2NE=2, B_NE2E=3, B_NF2F=4, B_F2NF=5,
                   B_WR_ONLY=6, B_RD_ONLY=7, B_BOTH=8, B_IDLE=9, B_BLK_WR=10, B_BLK_RD=11,
                   B_OCC0=12, B_OCC_LOW=13, B_OCC_MED=14, B_OCC_HIGH=15, B_OCC_MAX=16,
                   B_WR_FAST=17, B_RD_FAST=18, B_SIMILAR=19, B_PHASE=20, B_WRAP_W=21, B_WRAP_R=22,
                   B_RST_EMPTY=23, B_RST_FULL=24, B_RST_WR=25, B_RST_RD=26, B_RST_RECOV=27, B_RST_RECOV_RD=28;
    localparam int NG = AW + 1;                 // Gray bits per pointer

    // one vector per writer process
    logic [NB-1:0] ev_w = '0, ev_r = '0, ev_x = '0;
    logic [NG-1:0] gw_tog = '0, gr_tog = '0;    // each Gray bit seen toggling (write / read pointer)
    logic [14:0]   x_occ_op = '0;               // X1 occupancy(5) x write op(3)   [wr monitor]
    logic [5:0]    x_ratio_op = '0;             // X2 clock ratio(3) x write op(2) [wr monitor]
    logic [8:0]    x_rst = '0;                  // X3 FIFO state at reset(3) x activity(3) [reset monitor]
    logic          x_wrapw_rd = 1'b0;           // X4a write wrap with concurrent read   [wr monitor]
    logic          x_wrapr_wr = 1'b0;           // X4b read wrap with concurrent write   [rd monitor]

    wire [NB-1:0] ev = ev_w | ev_r | ev_x;

    // private monitor state
    logic prev_full = 0, prev_wmsb = 0, prev_empty = 1, prev_rmsb = 0;
    logic [AW:0] prev_wg = '0, prev_rg = '0, gx;
    integer w_seen_gen = 0, r_seen_gen = 0, reset_gen = 0;
    logic [31:0] occ_s = 0;
    integer ob, op, rat;
    wire active = wr_rst_n & rd_rst_n;

    // ---------------- write-clock monitor
    always @(posedge wr_clk) begin
        occ_s = occ;
        if (active) begin
            if (full)                  ev_w[B_FULL]    = 1;
            if (full && !prev_full)    ev_w[B_NF2F]    = 1;
            if (!full && prev_full)    ev_w[B_F2NF]    = 1;
            prev_full = full;
            if (wr_en && full)         ev_w[B_BLK_WR]  = 1;
            if (wr_ack && !rd_valid)   ev_w[B_WR_ONLY] = 1;
            if (wr_ack && rd_valid)    ev_w[B_BOTH]    = 1;
            if (!wr_en && !rd_en)      ev_w[B_IDLE]    = 1;
            if      (occ == 0)               begin ev_w[B_OCC0]     = 1; ob = 0; end
            else if (occ < DEPTH/4)          begin ev_w[B_OCC_LOW]  = 1; ob = 1; end
            else if (occ < (3*DEPTH)/4)      begin ev_w[B_OCC_MED]  = 1; ob = 2; end
            else if (occ < DEPTH)            begin ev_w[B_OCC_HIGH] = 1; ob = 3; end
            else                             begin ev_w[B_OCC_MAX]  = 1; ob = 4; end
            op = -1;
            if (wr_ack && !rd_valid) op = 0; else if (wr_ack && rd_valid) op = 1; else if (wr_en && full) op = 2;
            if (op >= 0) x_occ_op[ob*3 + op] = 1;
            // pointer wrap + Gray toggles
            if (wbin[AW] != prev_wmsb) begin
                ev_w[B_WRAP_W] = 1;
                if (rd_valid) x_wrapw_rd = 1;
            end
            prev_wmsb = wbin[AW];
            gx = wgray ^ prev_wg;
            for (int i = 0; i < NG; i++) if (gx[i]) gw_tog[i] = 1;
            prev_wg = wgray;
            if (wr_ack) begin
                if (wr_half*10 < rd_half*8)      begin ev_w[B_WR_FAST] = 1; rat = 0; end
                else if (rd_half*10 < wr_half*8) begin ev_w[B_RD_FAST] = 1; rat = 1; end
                else                             begin ev_w[B_SIMILAR] = 1; rat = 2; end
                x_ratio_op[rat*2 + (rd_valid ? 1 : 0)] = 1;
                if (phase_shift != 0)            ev_w[B_PHASE] = 1;
                if (w_seen_gen != reset_gen)     begin ev_w[B_RST_RECOV] = 1; w_seen_gen = reset_gen; end
            end
        end else begin
            prev_full = 0; prev_wmsb = 0; prev_wg = '0;
        end
    end

    // ---------------- read-clock monitor
    always @(posedge rd_clk) begin
        if (active) begin
            if (empty)                 ev_r[B_EMPTY]   = 1;
            if (!empty && prev_empty)  ev_r[B_E2NE]    = 1;
            if (empty && !prev_empty)  ev_r[B_NE2E]    = 1;
            prev_empty = empty;
            if (rd_en && empty)        ev_r[B_BLK_RD]  = 1;
            if (rd_valid && !wr_ack)   ev_r[B_RD_ONLY] = 1;
            if (rbin[AW] != prev_rmsb) begin
                ev_r[B_WRAP_R] = 1;
                if (wr_ack) x_wrapr_wr = 1;
            end
            prev_rmsb = rbin[AW];
            gx = rgray ^ prev_rg;
            for (int i = 0; i < NG; i++) if (gx[i]) gr_tog[i] = 1;
            prev_rg = rgray;
            if (rd_valid && r_seen_gen != reset_gen) begin ev_r[B_RST_RECOV_RD] = 1; r_seen_gen = reset_gen; end
        end else begin
            prev_empty = 1; prev_rmsb = 0; prev_rg = '0;
        end
    end

    // ---------------- reset monitor (single writer of ev_x / x_rst / reset_gen)
    integer st, act;
    always @(negedge wr_rst_n or negedge rd_rst_n) begin
        if (occ_s == 0)      begin ev_x[B_RST_EMPTY] = 1; st = 0; end
        else if (occ_s >= DEPTH) begin ev_x[B_RST_FULL] = 1; st = 2; end
        else st = 1;
        if (wr_en) ev_x[B_RST_WR] = 1;
        if (rd_en) ev_x[B_RST_RD] = 1;
        if (wr_en) x_rst[st*3 + 0] = 1;
        if (rd_en) x_rst[st*3 + 1] = 1;
        if (!wr_en && !rd_en) x_rst[st*3 + 2] = 1;
        reset_gen = reset_gen + 1;
    end

    // ---------------- reporting
    function integer count_bits(input logic [63:0] v, input integer n);
        integer i, c;
        begin c = 0; for (i = 0; i < n; i = i + 1) if (v[i]) c = c + 1; count_bits = c; end
    endfunction

    function integer evt_total(input integer dummy); begin evt_total = NB + 2*NG; end endfunction
    function integer evt_hit(input integer dummy);
        begin evt_hit = count_bits({{(64-NB){1'b0}}, ev}, NB) + count_bits({{(64-NG){1'b0}}, gw_tog}, NG)
                      + count_bits({{(64-NG){1'b0}}, gr_tog}, NG); end
    endfunction
    function integer x_total(input integer dummy); begin x_total = 15 + 6 + 9 + 2; end endfunction
    // Three X1 bins cannot occur in a correct FIFO and are EXCLUDED from the "reachable" figure:
    //   x_occ_op[1]  occupancy=0   x write+concurrent read  (no read can be accepted at occupancy 0)
    //   x_occ_op[12] occupancy=max x write-only             (no write can be accepted while full)
    //   x_occ_op[13] occupancy=max x write+read             (same reason)
    function integer x_total_reach(input integer dummy); begin x_total_reach = 15 + 6 + 9 + 2 - 3; end endfunction
    function integer x_hit_reach(input integer dummy);
        begin x_hit_reach = x_hit(0) - x_occ_op[1] - x_occ_op[12] - x_occ_op[13]; end
    endfunction
    function integer x_hit(input integer dummy);
        begin x_hit = count_bits({49'b0, x_occ_op}, 15) + count_bits({58'b0, x_ratio_op}, 6)
                    + count_bits({55'b0, x_rst}, 9) + x_wrapw_rd + x_wrapr_wr; end
    endfunction


    task pr(input integer idx, input [8*64-1:0] name);
        begin $display("  [%s] %0s", ev[idx] ? "HIT " : "MISS", name); end
    endtask

    task report;
        integer i, j;
        begin
            $display("=== FUNCTIONAL COVERAGE (hand-written bins; not code coverage, not covergroups) ===");
            $display("-- EVENT BINS --");
            pr(B_FULL,"status: full observed");       pr(B_EMPTY,"status: empty observed");
            pr(B_E2NE,"status: empty->nonempty");     pr(B_NE2E,"status: nonempty->empty");
            pr(B_NF2F,"status: nonfull->full");       pr(B_F2NF,"status: full->nonfull");
            pr(B_WR_ONLY,"op: write only (no concurrent read)"); pr(B_RD_ONLY,"op: read only (no concurrent write)");
            pr(B_BOTH,"op: write with concurrent read"); pr(B_IDLE,"op: no operation requested");
            pr(B_BLK_WR,"op: blocked write");         pr(B_BLK_RD,"op: blocked read");
            pr(B_OCC0,"occupancy: empty");            pr(B_OCC_LOW,"occupancy: low");
            pr(B_OCC_MED,"occupancy: medium");        pr(B_OCC_HIGH,"occupancy: high");
            pr(B_OCC_MAX,"occupancy: maximum");
            pr(B_WR_FAST,"cdc: write clock faster");  pr(B_RD_FAST,"cdc: read clock faster");
            pr(B_SIMILAR,"cdc: similar frequencies"); pr(B_PHASE,"cdc: shifted clock phase");
            pr(B_WRAP_W,"pointer wrap: write");       pr(B_WRAP_R,"pointer wrap: read");
            pr(B_RST_EMPTY,"reset at empty");         pr(B_RST_FULL,"reset at full");
            pr(B_RST_WR,"reset during write activity"); pr(B_RST_RD,"reset during read activity");
            pr(B_RST_RECOV,"recovery: first write after reset"); pr(B_RST_RECOV_RD,"recovery: first read after reset");
            for (i = 0; i < NG; i = i + 1) $display("  [%s] wgray bit %0d toggled", gw_tog[i] ? "HIT " : "MISS", i);
            for (i = 0; i < NG; i = i + 1) $display("  [%s] rgray bit %0d toggled", gr_tog[i] ? "HIT " : "MISS", i);
            $display("EVENT BINS COVERED: %0d / %0d", evt_hit(0), evt_total(0));
            $display("-- CROSS BINS --");
            $display(" X1 occupancy x write op (wo=write-only, wr=write+read, bw=blocked write)");
            $display("   occ=0     wo:%s wr:%s bw:%s", x_occ_op[0]?"HIT ":"MISS",  x_occ_op[1]?"HIT ":"EXCL",  x_occ_op[2]?"HIT ":"MISS");
            $display("   occ low   wo:%s wr:%s bw:%s", x_occ_op[3]?"HIT ":"MISS",  x_occ_op[4]?"HIT ":"MISS",  x_occ_op[5]?"HIT ":"MISS");
            $display("   occ med   wo:%s wr:%s bw:%s", x_occ_op[6]?"HIT ":"MISS",  x_occ_op[7]?"HIT ":"MISS",  x_occ_op[8]?"HIT ":"MISS");
            $display("   occ high  wo:%s wr:%s bw:%s", x_occ_op[9]?"HIT ":"MISS",  x_occ_op[10]?"HIT ":"MISS", x_occ_op[11]?"HIT ":"MISS");
            $display("   occ max   wo:%s wr:%s bw:%s", x_occ_op[12]?"HIT ":"EXCL", x_occ_op[13]?"HIT ":"EXCL", x_occ_op[14]?"HIT ":"MISS");
            $display(" X2 clock ratio x write op (wo / wr)");
            $display("   wr_faster wo:%s wr:%s", x_ratio_op[0]?"HIT ":"MISS", x_ratio_op[1]?"HIT ":"MISS");
            $display("   rd_faster wo:%s wr:%s", x_ratio_op[2]?"HIT ":"MISS", x_ratio_op[3]?"HIT ":"MISS");
            $display("   similar   wo:%s wr:%s", x_ratio_op[4]?"HIT ":"MISS", x_ratio_op[5]?"HIT ":"MISS");
            $display(" X3 FIFO state at reset x activity (wr active / rd active / idle)");
            $display("   empty     w:%s r:%s i:%s", x_rst[0]?"HIT ":"MISS", x_rst[1]?"HIT ":"MISS", x_rst[2]?"HIT ":"MISS");
            $display("   partial   w:%s r:%s i:%s", x_rst[3]?"HIT ":"MISS", x_rst[4]?"HIT ":"MISS", x_rst[5]?"HIT ":"MISS");
            $display("   full      w:%s r:%s i:%s", x_rst[6]?"HIT ":"MISS", x_rst[7]?"HIT ":"MISS", x_rst[8]?"HIT ":"MISS");
            $display(" X4 pointer wrap x concurrent op");
            $display("   write wrap with read:  %s", x_wrapw_rd ? "HIT " : "MISS");
            $display("   read wrap with write:  %s", x_wrapr_wr ? "HIT " : "MISS");
            $display("CROSS BINS COVERED (raw): %0d / %0d", x_hit(0), x_total(0));
            $display("CROSS BINS COVERED (3 unreachable bins excluded, marked EXCL): %0d / %0d", x_hit_reach(0), x_total_reach(0));
            $display("EXCL bins cannot occur in a correct FIFO; reasons in docs/verification_plan.md.");
            $display("=== END ===");
        end
    endtask
endmodule
`timescale 1ps/1ps
// Hand-written functional coverage collector (plain Verilog/SV, works in Icarus).
//   * EVENT bins : single-condition events (status, ops, occupancy, ratio/phase, wrap, Gray bit toggles, reset).
//   * CROSS bins : combinations of those events. Reported SEPARATELY from event bins.
// This is NOT RTL code coverage and NOT covergroup (native) coverage.
// Race-freedom: every bit vector is written by exactly one process (wr monitor, rd monitor or reset monitor)
// and the totals are the OR of the vectors, so processes never read-modify-write the same variable.
module coverage #(parameter int AW = 4) (
    input logic        wr_clk, rd_clk, wr_rst_n, rd_rst_n,
    input logic        wr_en, wr_ack, full, rd_en, rd_valid, empty,
    input logic [AW:0] wbin, wgray, rbin, rgray,
    input logic [31:0] occ,
    input logic [31:0] wr_half, rd_half, phase_shift
);
    localparam int DEPTH = 1 << AW;
    localparam int NB = 29;
    localparam int B_FULL=0, B_EMPTY=1, B_E2NE=2, B_NE2E=3, B_NF2F=4, B_F2NF=5,
                   B_WR_ONLY=6, B_RD_ONLY=7, B_BOTH=8, B_IDLE=9, B_BLK_WR=10, B_BLK_RD=11,
                   B_OCC0=12, B_OCC_LOW=13, B_OCC_MED=14, B_OCC_HIGH=15, B_OCC_MAX=16,
                   B_WR_FAST=17, B_RD_FAST=18, B_SIMILAR=19, B_PHASE=20, B_WRAP_W=21, B_WRAP_R=22,
                   B_RST_EMPTY=23, B_RST_FULL=24, B_RST_WR=25, B_RST_RD=26, B_RST_RECOV=27, B_RST_RECOV_RD=28;
    localparam int NG = AW + 1;                 // Gray bits per pointer

    // one vector per writer process
    logic [NB-1:0] ev_w = '0, ev_r = '0, ev_x = '0;
    logic [NG-1:0] gw_tog = '0, gr_tog = '0;    // each Gray bit seen toggling (write / read pointer)
    logic [14:0]   x_occ_op = '0;               // X1 occupancy(5) x write op(3)   [wr monitor]
    logic [5:0]    x_ratio_op = '0;             // X2 clock ratio(3) x write op(2) [wr monitor]
    logic [8:0]    x_rst = '0;                  // X3 FIFO state at reset(3) x activity(3) [reset monitor]
    logic          x_wrapw_rd = 1'b0;           // X4a write wrap with concurrent read   [wr monitor]
    logic          x_wrapr_wr = 1'b0;           // X4b read wrap with concurrent write   [rd monitor]

    wire [NB-1:0] ev = ev_w | ev_r | ev_x;

    // private monitor state
    logic prev_full = 0, prev_wmsb = 0, prev_empty = 1, prev_rmsb = 0;
    logic [AW:0] prev_wg = '0, prev_rg = '0, gx;
    integer w_seen_gen = 0, r_seen_gen = 0, reset_gen = 0;
    logic [31:0] occ_s = 0;
    integer ob, op, rat;
    wire active = wr_rst_n & rd_rst_n;

    // ---------------- write-clock monitor
    always @(posedge wr_clk) begin
        occ_s = occ;
        if (active) begin
            if (full)                  ev_w[B_FULL]    = 1;
            if (full && !prev_full)    ev_w[B_NF2F]    = 1;
            if (!full && prev_full)    ev_w[B_F2NF]    = 1;
            prev_full = full;
            if (wr_en && full)         ev_w[B_BLK_WR]  = 1;
            if (wr_ack && !rd_valid)   ev_w[B_WR_ONLY] = 1;
            if (wr_ack && rd_valid)    ev_w[B_BOTH]    = 1;
            if (!wr_en && !rd_en)      ev_w[B_IDLE]    = 1;
            if      (occ == 0)               begin ev_w[B_OCC0]     = 1; ob = 0; end
            else if (occ < DEPTH/4)          begin ev_w[B_OCC_LOW]  = 1; ob = 1; end
            else if (occ < (3*DEPTH)/4)      begin ev_w[B_OCC_MED]  = 1; ob = 2; end
            else if (occ < DEPTH)            begin ev_w[B_OCC_HIGH] = 1; ob = 3; end
            else                             begin ev_w[B_OCC_MAX]  = 1; ob = 4; end
            op = -1;
            if (wr_ack && !rd_valid) op = 0; else if (wr_ack && rd_valid) op = 1; else if (wr_en && full) op = 2;
            if (op >= 0) x_occ_op[ob*3 + op] = 1;
            // pointer wrap + Gray toggles
            if (wbin[AW] != prev_wmsb) begin
                ev_w[B_WRAP_W] = 1;
                if (rd_valid) x_wrapw_rd = 1;
            end
            prev_wmsb = wbin[AW];
            gx = wgray ^ prev_wg;
            for (int i = 0; i < NG; i++) if (gx[i]) gw_tog[i] = 1;
            prev_wg = wgray;
            if (wr_ack) begin
                if (wr_half*10 < rd_half*8)      begin ev_w[B_WR_FAST] = 1; rat = 0; end
                else if (rd_half*10 < wr_half*8) begin ev_w[B_RD_FAST] = 1; rat = 1; end
                else                             begin ev_w[B_SIMILAR] = 1; rat = 2; end
                x_ratio_op[rat*2 + (rd_valid ? 1 : 0)] = 1;
                if (phase_shift != 0)            ev_w[B_PHASE] = 1;
                if (w_seen_gen != reset_gen)     begin ev_w[B_RST_RECOV] = 1; w_seen_gen = reset_gen; end
            end
        end else begin
            prev_full = 0; prev_wmsb = 0; prev_wg = '0;
        end
    end

    // ---------------- read-clock monitor
    always @(posedge rd_clk) begin
        if (active) begin
            if (empty)                 ev_r[B_EMPTY]   = 1;
            if (!empty && prev_empty)  ev_r[B_E2NE]    = 1;
            if (empty && !prev_empty)  ev_r[B_NE2E]    = 1;
            prev_empty = empty;
            if (rd_en && empty)        ev_r[B_BLK_RD]  = 1;
            if (rd_valid && !wr_ack)   ev_r[B_RD_ONLY] = 1;
            if (rbin[AW] != prev_rmsb) begin
                ev_r[B_WRAP_R] = 1;
                if (wr_ack) x_wrapr_wr = 1;
            end
            prev_rmsb = rbin[AW];
            gx = rgray ^ prev_rg;
            for (int i = 0; i < NG; i++) if (gx[i]) gr_tog[i] = 1;
            prev_rg = rgray;
            if (rd_valid && r_seen_gen != reset_gen) begin ev_r[B_RST_RECOV_RD] = 1; r_seen_gen = reset_gen; end
        end else begin
            prev_empty = 1; prev_rmsb = 0; prev_rg = '0;
        end
    end

    // ---------------- reset monitor (single writer of ev_x / x_rst / reset_gen)
    integer st, act;
    always @(negedge wr_rst_n or negedge rd_rst_n) begin
        if (occ_s == 0)      begin ev_x[B_RST_EMPTY] = 1; st = 0; end
        else if (occ_s >= DEPTH) begin ev_x[B_RST_FULL] = 1; st = 2; end
        else st = 1;
        if (wr_en) ev_x[B_RST_WR] = 1;
        if (rd_en) ev_x[B_RST_RD] = 1;
        if (wr_en) x_rst[st*3 + 0] = 1;
        if (rd_en) x_rst[st*3 + 1] = 1;
        if (!wr_en && !rd_en) x_rst[st*3 + 2] = 1;
        reset_gen = reset_gen + 1;
    end

    // ---------------- reporting
    function integer count_bits(input logic [63:0] v, input integer n);
        integer i, c;
        begin c = 0; for (i = 0; i < n; i = i + 1) if (v[i]) c = c + 1; count_bits = c; end
    endfunction

    function integer evt_total(input integer dummy); begin evt_total = NB + 2*NG; end endfunction
    function integer evt_hit(input integer dummy);
        begin evt_hit = count_bits({{(64-NB){1'b0}}, ev}, NB) + count_bits({{(64-NG){1'b0}}, gw_tog}, NG)
                      + count_bits({{(64-NG){1'b0}}, gr_tog}, NG); end
    endfunction
    function integer x_total(input integer dummy); begin x_total = 15 + 6 + 9 + 2; end endfunction
    function integer x_hit(input integer dummy);
        begin x_hit = count_bits({49'b0, x_occ_op}, 15) + count_bits({58'b0, x_ratio_op}, 6)
                    + count_bits({55'b0, x_rst}, 9) + x_wrapw_rd + x_wrapr_wr; end
    endfunction


    task pr(input integer idx, input [8*64-1:0] name);
        begin $display("  [%s] %0s", ev[idx] ? "HIT " : "MISS", name); end
    endtask

    task report;
        integer i, j;
        begin
            $display("=== FUNCTIONAL COVERAGE (hand-written bins; not code coverage, not covergroups) ===");
            $display("-- EVENT BINS --");
            pr(B_FULL,"status: full observed");       pr(B_EMPTY,"status: empty observed");
            pr(B_E2NE,"status: empty->nonempty");     pr(B_NE2E,"status: nonempty->empty");
            pr(B_NF2F,"status: nonfull->full");       pr(B_F2NF,"status: full->nonfull");
            pr(B_WR_ONLY,"op: write only (no concurrent read)"); pr(B_RD_ONLY,"op: read only (no concurrent write)");
            pr(B_BOTH,"op: write with concurrent read"); pr(B_IDLE,"op: no operation requested");
            pr(B_BLK_WR,"op: blocked write");         pr(B_BLK_RD,"op: blocked read");
            pr(B_OCC0,"occupancy: empty");            pr(B_OCC_LOW,"occupancy: low");
            pr(B_OCC_MED,"occupancy: medium");        pr(B_OCC_HIGH,"occupancy: high");
            pr(B_OCC_MAX,"occupancy: maximum");
            pr(B_WR_FAST,"cdc: write clock faster");  pr(B_RD_FAST,"cdc: read clock faster");
            pr(B_SIMILAR,"cdc: similar frequencies"); pr(B_PHASE,"cdc: shifted clock phase");
            pr(B_WRAP_W,"pointer wrap: write");       pr(B_WRAP_R,"pointer wrap: read");
            pr(B_RST_EMPTY,"reset at empty");         pr(B_RST_FULL,"reset at full");
            pr(B_RST_WR,"reset during write activity"); pr(B_RST_RD,"reset during read activity");
            pr(B_RST_RECOV,"recovery: first write after reset"); pr(B_RST_RECOV_RD,"recovery: first read after reset");
            for (i = 0; i < NG; i = i + 1) $display("  [%s] wgray bit %0d toggled", gw_tog[i] ? "HIT " : "MISS", i);
            for (i = 0; i < NG; i = i + 1) $display("  [%s] rgray bit %0d toggled", gr_tog[i] ? "HIT " : "MISS", i);
            $display("EVENT BINS COVERED: %0d / %0d", evt_hit(0), evt_total(0));
            $display("-- CROSS BINS --");
            $display(" X1 occupancy x write op (wo=write-only, wr=write+read, bw=blocked write)");
            $display("   occ=0     wo:%s wr:%s bw:%s", x_occ_op[0]?"HIT ":"MISS",  x_occ_op[1]?"HIT ":"MISS",  x_occ_op[2]?"HIT ":"MISS");
            $display("   occ low   wo:%s wr:%s bw:%s", x_occ_op[3]?"HIT ":"MISS",  x_occ_op[4]?"HIT ":"MISS",  x_occ_op[5]?"HIT ":"MISS");
            $display("   occ med   wo:%s wr:%s bw:%s", x_occ_op[6]?"HIT ":"MISS",  x_occ_op[7]?"HIT ":"MISS",  x_occ_op[8]?"HIT ":"MISS");
            $display("   occ high  wo:%s wr:%s bw:%s", x_occ_op[9]?"HIT ":"MISS",  x_occ_op[10]?"HIT ":"MISS", x_occ_op[11]?"HIT ":"MISS");
            $display("   occ max   wo:%s wr:%s bw:%s", x_occ_op[12]?"HIT ":"MISS", x_occ_op[13]?"HIT ":"MISS", x_occ_op[14]?"HIT ":"MISS");
            $display(" X2 clock ratio x write op (wo / wr)");
            $display("   wr_faster wo:%s wr:%s", x_ratio_op[0]?"HIT ":"MISS", x_ratio_op[1]?"HIT ":"MISS");
            $display("   rd_faster wo:%s wr:%s", x_ratio_op[2]?"HIT ":"MISS", x_ratio_op[3]?"HIT ":"MISS");
            $display("   similar   wo:%s wr:%s", x_ratio_op[4]?"HIT ":"MISS", x_ratio_op[5]?"HIT ":"MISS");
            $display(" X3 FIFO state at reset x activity (wr active / rd active / idle)");
            $display("   empty     w:%s r:%s i:%s", x_rst[0]?"HIT ":"MISS", x_rst[1]?"HIT ":"MISS", x_rst[2]?"HIT ":"MISS");
            $display("   partial   w:%s r:%s i:%s", x_rst[3]?"HIT ":"MISS", x_rst[4]?"HIT ":"MISS", x_rst[5]?"HIT ":"MISS");
            $display("   full      w:%s r:%s i:%s", x_rst[6]?"HIT ":"MISS", x_rst[7]?"HIT ":"MISS", x_rst[8]?"HIT ":"MISS");
            $display(" X4 pointer wrap x concurrent op");
            $display("   write wrap with read:  %s", x_wrapw_rd ? "HIT " : "MISS");
            $display("   read wrap with write:  %s", x_wrapr_wr ? "HIT " : "MISS");
            $display("CROSS BINS COVERED: %0d / %0d", x_hit(0), x_total(0));
            $display("Unreachable/unjustified bins are NOT excluded automatically; see docs/verification_plan.md.");
            $display("=== END ===");
        end
    endtask
endmodule
