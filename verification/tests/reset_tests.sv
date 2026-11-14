// Stage 3a: SYSTEM reset only (both domains reset together). Single-domain reset is NOT supported
// (see docs/architecture.md), so T42/T43 are not implemented.
task run_reset_tests;
    begin
        begin_test(47, "reset with FIFO full");
        sys_reset; fill;
        check(full === 1'b1, "precondition: full");
        reset_mid_traffic;
        check(full === 1'b0 && empty === 1'b1, "flags after reset");
        check(occ == 0, "reference flushed");
        traffic(300, 100, 100);   // recovery
        end_test;

        begin_test(48, "reset with FIFO empty");
        sys_reset; reset_mid_traffic;
        check(empty === 1'b1 && full === 1'b0, "flags after reset");
        traffic(200, 80, 80); end_test;

        begin_test(46, "reset during simultaneous operation");
        sys_reset; wr_prob = 100; rd_prob = 100; wait_wr(137);
        reset_mid_traffic;
        check(empty === 1'b1 && full === 1'b0, "flags after reset");
        traffic(500, 100, 100); end_test;

        begin_test(44, "reset during active write only");
        sys_reset; wr_prob = 100; rd_prob = 0; wait_wr(7);
        reset_mid_traffic;
        check(empty === 1'b1 && full === 1'b0 && occ == 0, "clean after reset");
        traffic(200, 100, 100); end_test;

        begin_test(45, "reset during active read only");
        sys_reset; write_n(DEPTH - 1); wait_rd(6); rd_prob = 100; wait_rd(5);
        reset_mid_traffic;
        check(empty === 1'b1 && full === 1'b0 && occ == 0, "clean after reset");
        traffic(200, 100, 100); end_test;

        begin_test(49, "reset recovery data integrity");
        sys_reset; write_n(5); wait_rd(6); reset_mid_traffic;
        write_n(6); wait_rd(6);
        check(occ == 6, "only post-reset data expected");
        drain; end_test;
    end
endtask
