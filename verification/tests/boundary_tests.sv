// Stage 2a: pointer and boundary tests (T16-T20 subset).
task run_boundary_tests;
    integer i;
    begin
        begin_test(16, "max/min occupancy");
        sys_reset; fill;
        check(occ == DEPTH && full === 1'b1, "max occupancy with full flag");
        drain;
        check(occ == 0 && empty === 1'b1, "min occupancy with empty flag");
        end_test;

        begin_test(18, "repeated fill and drain x8");
        sys_reset;
        for (i = 0; i < 8; i = i + 1) begin fill; drain; end   // 8*16 words: pointers wrap several times
        end_test;

        begin_test(20, "full/empty boundary transitions");
        sys_reset;
        write_n(DEPTH - 1); wait_wr(2);
        check(full === 1'b0, "not full at DEPTH-1");
        write_n(1);
        check(full === 1'b1, "full right after DEPTH-th write");
        wait_rd(6); read_n(1); wait_wr(6);
        check(full === 1'b0, "full clears after one read");
        drain;
        write_n(1); wait_rd(6); read_n(1);
        check(empty === 1'b1, "empty right after last read");
        drain; end_test;
    end
endtask
