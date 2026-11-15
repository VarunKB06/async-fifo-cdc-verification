// Stage 2b: concurrent traffic across clock ratios/phases (T21-T26, T35-T38 subset).
task run_cdc_tests;
    integer i;
    begin
        begin_test(21, "simultaneous r/w 100MHz/75MHz");
        sys_reset; set_clocks(5000, 6667);
        traffic(1500, 100, 100); end_test;

        begin_test(23, "write clock faster than read");
        sys_reset; set_clocks(2000, 8000);
        traffic(1500, 100, 100); end_test;

        begin_test(24, "read clock faster than write");
        sys_reset; set_clocks(8000, 2000);
        traffic(600, 100, 100); end_test;

        begin_test(26, "unequal odd periods");
        sys_reset; set_clocks(5000, 7333);
        traffic(1000, 70, 60); end_test;

        begin_test(36, "shifted read clock phase");
        sys_reset; set_clocks(5000, 5000);
        rd_skew = 2500; phase_total = phase_total + 2500; wait_rd(3);
        traffic(1000, 100, 100);
        rd_skew = 1234; phase_total = phase_total + 1234; wait_rd(3);
        traffic(1000, 100, 100); end_test;

        begin_test(37, "write 10x faster than read");
        sys_reset; set_clocks(1000, 10000);
        traffic(3000, 100, 100); end_test;

        begin_test(38, "read 10x faster than write");
        sys_reset; set_clocks(10000, 1000);
        traffic(300, 100, 100); end_test;

        set_clocks(5000, 6667);
    end
endtask

// Stage 2c: CDC pointer-synchronization latency and near-boundary concurrency (T27-T29, T31-T33).
task run_cdc_sync_tests;
    integer i;
    begin
        begin_test(31, "write ptr sync latency (empty clears)");
        sys_reset; set_clocks(5000, 6667);
        write_n(1);                         // accepted at the last wr edge (returns 1 ps after it)
        measure_empty_clear;
        check(lat_n == SYNC_STAGES + 1, "empty clears after SYNC_STAGES+1 rd edges");
        drain; end_test;

        begin_test(32, "read ptr sync latency (full clears)");
        sys_reset; set_clocks(5000, 6667);
        fill; check(full === 1'b1, "precondition: full");
        read_n(1);
        measure_full_clear;
        check(lat_n == SYNC_STAGES + 1, "full clears after exactly SYNC_STAGES+1 wr edges");
        drain; end_test;

        begin_test(33, "sync latency, several clock ratios");
        for (i = 0; i < 4; i = i + 1) begin
            sys_reset;
            case (i) 0: set_clocks(2000, 9000); 1: set_clocks(9000, 2000); 2: set_clocks(5000, 5000); default: set_clocks(7000, 3100); endcase
            write_n(1); measure_empty_clear;
            check(lat_n == SYNC_STAGES + 1, "empty latency");
            drain;
        end
        set_clocks(5000, 6667); end_test;

        begin_test(27, "simultaneous ops near full");
        sys_reset; set_clocks(5000, 6667);
        write_n(DEPTH - 2); wait_rd(6);
        traffic(600, 100, 95); end_test;

        begin_test(28, "simultaneous ops near empty");
        sys_reset; write_n(1); wait_rd(6);
        traffic(600, 55, 100); end_test;

        begin_test(29, "repeated concurrent fill and drain");
        sys_reset;
        for (i = 0; i < 6; i = i + 1) begin traffic(150, 100, 25); traffic(150, 25, 100); end
        end_test;

        // T59 closes the cross bins "blocked write at occupancy 0" and "blocked write at low occupancy".
        // `full` lags the read pointer by SYNC_STAGES+1 write edges. With a 10x faster read clock and wr_en held
        // high, the FIFO is drained (16 or 14 words) before `full` clears, so write attempts are blocked while the
        // true occupancy is 0 (i = 0) or 2 (i = 1).
        begin_test(59, "blocked write, stale full, occ 0/low");
        for (i = 0; i < 2; i = i + 1) begin
            sys_reset; set_clocks(10000, 1000);
            wr_prob = 100; rd_prob = 0; wait_wr(DEPTH + 6);       // fill; wr_en stays high (blocked once full)
            check(full === 1'b1 && occ == DEPTH, "precondition: full FIFO, wr_en still high");
            read_n(i == 0 ? DEPTH : DEPTH - 2);                   // fast reads while wr_en stays high
            wait_wr(8);                                           // stale full clears, writes resume
            drain;
        end
        set_clocks(5000, 6667);
        end_test;
    end
endtask
