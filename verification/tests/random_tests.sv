// Stage 3b: reproducible randomized tests (seed from +seed=N, printed in the summary).
task run_random_tests;
    integer it;
    begin
        begin_test(51, "random traffic fixed clocks");
        sys_reset; set_clocks(5000, 6667);
        for (it = 0; it < 10; it = it + 1) traffic(300, 10 + rnd(91), 10 + rnd(91));
        end_test;

        begin_test(54, "random clock ratios");
        sys_reset;
        for (it = 0; it < 12; it = it + 1) begin
            wr_half = 1000 + rnd(14000); rd_half = 1000 + rnd(14000);
            wait_wr(2); wait_rd(2);
            $display("   iter %0d wr_half=%0d rd_half=%0d", it, wr_half, rd_half);
            traffic(300, 20 + rnd(81), 20 + rnd(81));
        end
        set_clocks(5000, 6667); end_test;

        begin_test(55, "random reset scenarios");
        sys_reset;
        for (it = 0; it < 8; it = it + 1) begin
            wr_prob = 30 + rnd(71); rd_prob = 30 + rnd(71);
            wait_wr(20 + rnd(200));
            reset_mid_traffic;
            check(empty === 1'b1 && full === 1'b0, "flags after random reset");
            traffic(150, 30 + rnd(71), 30 + rnd(71));
        end
        end_test;

        begin_test(57, "random boundary conditions");
        sys_reset; set_clocks(5000, 6667);
        for (it = 0; it < 12; it = it + 1) begin
            write_n(rnd(DEPTH));
            wait_rd(6);
            traffic(150, (rnd(2) ? 95 : 5), (rnd(2) ? 95 : 5));
        end
        end_test;

        begin_test(58, "random fill and drain cycles");
        sys_reset; set_clocks(5000, 6667);
        for (it = 0; it < 12; it = it + 1) begin
            wr_prob = 100; rd_prob = rnd(30); wait_wr(1 + rnd(2 * DEPTH));
            drain;
        end
        end_test;

        begin_test(56, "long random stress");
        sys_reset; set_clocks(5000, 6667);
        traffic(20000, 60, 55);
        end_test;
    end
endtask
