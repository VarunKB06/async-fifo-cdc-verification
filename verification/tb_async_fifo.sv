`timescale 1ps/1ps
// Procedural self-checking testbench. Run:  +STAGE=0 (all) | 1 | 2 | 3   +seed=N
// Drivers use non-blocking assignments after each clock edge; monitors sample pre-edge values, so there is
// no driver/monitor race inside a domain. Reset is asserted asynchronously, released synchronously.
module tb_async_fifo;
    localparam int DW = 8, AW = 4, DEPTH = (1 << AW), SYNC_STAGES = 2;

    reg wr_clk = 0, rd_clk = 0, wr_rst_n = 0, rd_rst_n = 0, wr_en = 0, rd_en = 0;
    reg  [DW-1:0] din = 0;
    wire [DW-1:0] dout;
    wire full, empty, wr_ack, rd_valid;

    integer wr_half = 5000, rd_half = 6667, rd_skew = 0, phase_total = 0;   // ps (100 MHz / ~75 MHz)
    integer wr_prob = 0, rd_prob = 0;
    reg     wr_manual = 0, rd_manual = 0;
    integer seed, seed0, stage, dcnt = 0;
    integer tb_checks = 0, tb_errors = 0, tests_run = 0, tests_pass = 0, tests_fail = 0, err_base = 0;
    integer n_wr_acc = 0, n_rd_acc = 0, watchdog = 0;
    integer cur_id; reg [8*40-1:0] cur_name;

    async_fifo #(.DATA_WIDTH(DW), .ADDR_WIDTH(AW), .SYNC_STAGES(SYNC_STAGES)) dut (
        .wr_clk(wr_clk), .wr_rst_n(wr_rst_n), .wr_en(wr_en), .din(din), .full(full), .wr_ack(wr_ack),
        .rd_clk(rd_clk), .rd_rst_n(rd_rst_n), .rd_en(rd_en), .dout(dout), .empty(empty), .rd_valid(rd_valid));

    wire [31:0] occ;
    scoreboard #(.DW(DW), .DEPTH(DEPTH), .SYNC_STAGES(SYNC_STAGES)) sb (
        .wr_clk(wr_clk), .rd_clk(rd_clk), .wr_rst_n(wr_rst_n), .rd_rst_n(rd_rst_n),
        .wr_en(wr_en), .wr_ack(wr_ack), .full(full), .din(din),
        .rd_en(rd_en), .rd_valid(rd_valid), .empty(empty), .dout(dout), .occ(occ));

    assertions #(.AW(AW), .SYNC_STAGES(SYNC_STAGES)) asr (
        .wr_clk(wr_clk), .rd_clk(rd_clk), .wr_rst_n(wr_rst_n), .rd_rst_n(rd_rst_n),
        .wr_en(wr_en), .wr_ack(wr_ack), .full(full), .rd_en(rd_en), .rd_valid(rd_valid), .empty(empty),
        .wbin(dut.wbin), .wgray(dut.wgray), .rbin(dut.rbin), .rgray(dut.rgray),
        .wgray_sync(dut.wgray_sync), .rgray_sync(dut.rgray_sync), .mem_we(dut.u_mem.wr_we));

    coverage #(.AW(AW)) cov (
        .wr_clk(wr_clk), .rd_clk(rd_clk), .wr_rst_n(wr_rst_n), .rd_rst_n(rd_rst_n),
        .wr_en(wr_en), .wr_ack(wr_ack), .full(full), .rd_en(rd_en), .rd_valid(rd_valid), .empty(empty),
        .wbin(dut.wbin), .wgray(dut.wgray), .rbin(dut.rbin), .rgray(dut.rgray), .occ(occ),
        .wr_half(wr_half), .rd_half(rd_half), .phase_shift(phase_total));

    // ---------------- independent clocks
    always #(wr_half) wr_clk = ~wr_clk;
    initial forever begin #(rd_half + rd_skew); rd_skew = 0; rd_clk = ~rd_clk; end

    // ---------------- helpers
    function integer rnd(input integer m);
        begin rnd = {$random(seed)} % m; end
    endfunction

    task check(input cond, input [8*48-1:0] msg);
        begin
            tb_checks = tb_checks + 1;
            if (!cond) begin tb_errors = tb_errors + 1; $display("[TB FAIL] t=%0t %0s", $time, msg); end
        end
    endtask

    // ---------------- random background drivers
    always @(posedge wr_clk) if (!wr_manual) begin
        wr_en <= (wr_prob > 0) && (rnd(100) < wr_prob);
        din   <= rnd(256);
    end
    always @(posedge rd_clk) if (!rd_manual) rd_en <= (rd_prob > 0) && (rnd(100) < rd_prob);

    always @(posedge wr_clk) if (wr_ack) n_wr_acc = n_wr_acc + 1;
    always @(posedge rd_clk) if (rd_valid) n_rd_acc = n_rd_acc + 1;

    // ---------------- directed drivers (exactly n attempts)
    task write_n(input integer n);
        integer i;
        begin
            wr_manual = 1;
            for (i = 0; i < n; i = i + 1) begin
                @(posedge wr_clk); wr_en <= 1; din <= dcnt[DW-1:0]; dcnt = dcnt + 1;
            end
            @(posedge wr_clk); wr_en <= 0; wr_manual = 0; #1;
        end
    endtask

    task read_n(input integer n);
        integer i;
        begin
            rd_manual = 1;
            for (i = 0; i < n; i = i + 1) begin @(posedge rd_clk); rd_en <= 1; end
            @(posedge rd_clk); rd_en <= 0; rd_manual = 0; #1;
        end
    endtask

    task wait_wr(input integer n); begin repeat (n) @(posedge wr_clk); #1; end endtask
    task wait_rd(input integer n); begin repeat (n) @(posedge rd_clk); #1; end endtask
    task set_clocks(input integer w, input integer r); begin wr_half = w; rd_half = r; wait_wr(3); wait_rd(3); end endtask

    // ---------------- reset
    task release_both;
        begin
            fork
                begin @(posedge wr_clk); wr_rst_n <= 1; end
                begin @(posedge rd_clk); rd_rst_n <= 1; end
            join
            wait_wr(4); wait_rd(4);
        end
    endtask

    task sys_reset;                       // quiesce, assert async, hold, release synchronously
        begin
            wr_prob = 0; rd_prob = 0; wr_manual = 0; rd_manual = 0;
            wait_wr(3); wait_rd(3);
            #1000; wr_rst_n = 0; rd_rst_n = 0;
            wait_wr(4); wait_rd(4);
            release_both;
        end
    endtask

    task reset_mid_traffic;               // reset while traffic knobs are still active
        begin
            #1000; wr_rst_n = 0; rd_rst_n = 0;
            wait_wr(4);
            wr_prob = 0; rd_prob = 0;     // protocol: no traffic across reset release
            wait_rd(4);
            release_both;
        end
    endtask

    task fill;                            // write until full
        begin wr_prob = 100; rd_prob = 0; wait_wr(DEPTH + 4); wr_prob = 0; wait_wr(3); end
    endtask

    task drain;                           // stop writes, read everything, check scoreboard is empty
        integer guard;
        begin
            wr_prob = 0; rd_prob = 0;
            wait_wr(4); wait_rd(6);
            rd_prob = 100; guard = 0;
            while ((empty !== 1'b1 || occ != 0) && guard < 40 * DEPTH + 200) begin
                @(posedge rd_clk); guard = guard + 1;
            end
            rd_prob = 0; wait_rd(3);
            check(occ == 0,     "drain: reference queue empty (no data loss)");
            check(empty === 1,  "drain: empty flag set");
        end
    endtask

    task traffic(input integer cycles, input integer wp, input integer rp);
        begin wr_prob = wp; rd_prob = rp; repeat (cycles) @(posedge wr_clk); drain; end
    endtask

    // ---------------- test bookkeeping
    task begin_test(input integer id, input [8*40-1:0] name);
        begin
            cur_id = id; cur_name = name;
            err_base = tb_errors + sb.errors + asr.fail_count;
            $display("[T%0d] START %0s", id, name);
        end
    endtask

    task end_test;
        integer d;
        begin
            d = tb_errors + sb.errors + asr.fail_count - err_base;
            tests_run = tests_run + 1;
            if (d == 0) begin tests_pass = tests_pass + 1; $display("[T%0d] PASS  %0s", cur_id, cur_name); end
            else begin tests_fail = tests_fail + 1; $display("[T%0d] FAIL  %0s (%0d new errors)", cur_id, cur_name, d); end
        end
    endtask

    function run_stage(input integer s); begin run_stage = (stage == 0) || (stage == s); end endfunction

    `include "basic_tests.sv"
    `include "boundary_tests.sv"
    `include "cdc_tests.sv"
    `include "reset_tests.sv"
    `include "random_tests.sv"

    // ---- directed latency measurements (used by cdc_tests)
    integer lat_n;
    task measure_empty_clear;            // edges of rd_clk (after the accepted write) until empty drops
        begin
            lat_n = 0;
            while (empty !== 1'b0 && lat_n < 50) begin @(posedge rd_clk); #1; lat_n = lat_n + 1; end
        end
    endtask
    task measure_full_clear;             // edges of wr_clk (after the accepted read) until full drops
        begin
            lat_n = 0;
            while (full !== 1'b0 && lat_n < 50) begin @(posedge wr_clk); #1; lat_n = lat_n + 1; end
        end
    endtask

    task summary;
        integer total_checks;
        reg ok;
        begin
            cov.report;
            $display("=== ASSERTION SUMMARY ===");
            $display("mode: %0s", asr.NATIVE_SVA ? "native SVA" : "PROCEDURAL checkers (not native SVA)");
            $display("assertion/check failures: %0d", asr.fail_count);
            if (!asr.NATIVE_SVA) $display("procedural check evaluations (wr+rd edges): %0d", asr.checks_run);
            $display("=== END ===");
            total_checks = tb_checks + sb.checks;
            ok = (tests_run > 0) && (tests_fail == 0) && (sb.errors == 0) && (asr.fail_count == 0) && !watchdog;
            $display("=== SUMMARY ===");
            $display("seed: %0d   stage: %0d", seed0, stage);
            $display("total tests: %0d", tests_run);
            $display("passed tests: %0d", tests_pass);
            $display("failed tests: %0d", tests_fail);
            $display("total checks: %0d (tb %0d + scoreboard %0d)", total_checks, tb_checks, sb.checks);
            $display("scoreboard writes/reads compared: %0d / %0d", sb.writes, sb.reads);
            $display("assertion failures: %0d", asr.fail_count);
            $display("scoreboard errors: %0d", sb.errors);
            $display("functional EVENT bins covered: %0d / %0d", cov.evt_hit(0), cov.evt_total(0));
            $display("functional CROSS bins covered: %0d / %0d", cov.x_hit(0), cov.x_total(0));
            $display("functional CROSS bins covered (3 unreachable excluded): %0d / %0d", cov.x_hit_reach(0), cov.x_total_reach(0));
            if (watchdog) $display("WATCHDOG TIMEOUT");
            $display("FINAL: %0s", ok ? "PASS" : "FAIL");
            $display("=== END ===");
        end
    endtask

    initial begin
        repeat (1000) #10_000_000;
        watchdog = 1; $display("[WATCHDOG] simulation timeout"); summary; $finish;
    end

    initial begin
        if (!$value$plusargs("seed=%d", seed))   seed = 1;
        seed0 = seed;                      // $random(seed) modifies seed; keep the requested value for reporting
        if (!$value$plusargs("STAGE=%d", stage)) stage = 0;
        // Waveform dump only on request (+vcd). CI passes +vcd; plain local/Vivado runs are unaffected.
        // The waveforms/ directory must exist before the simulation starts.
        if ($test$plusargs("vcd")) begin
            $dumpfile("waveforms/tb_async_fifo.vcd");
            $dumpvars(0, tb_async_fifo);
        end
        $display("=== tb_async_fifo: stage=%0d seed=%0d ===", stage, seed0);
        wait_wr(2);
        if (run_stage(1)) run_basic_tests;
        if (run_stage(2)) begin run_boundary_tests; run_cdc_tests; run_cdc_sync_tests; end
        if (run_stage(3)) begin run_reset_tests; run_random_tests; end
        summary;
        $finish;
    end
endmodule
