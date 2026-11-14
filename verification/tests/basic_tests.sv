// Stage 1: T1-T10. Included inside tb_async_fifo (uses its tasks/signals).
task run_basic_tests;
    integer base, i;
    begin
        begin_test(1, "initial reset behaviour");
        sys_reset;
        check(empty === 1'b1, "empty after reset");
        check(full  === 1'b0, "full low after reset");
        check(wr_ack === 1'b0 && rd_valid === 1'b0, "no ack/valid after reset");
        check(occ == 0, "reference queue empty after reset");
        end_test;

        begin_test(2, "single write and read");
        sys_reset; write_n(1); wait_rd(6);
        check(empty === 1'b0, "empty deasserts after write");
        read_n(1); wait_rd(2);
        check(empty === 1'b1, "empty after reading the only word");
        end_test;

        begin_test(3, "multiple sequential writes");
        sys_reset; write_n(8); wait_rd(6);
        check(occ == 8, "8 words buffered");
        check(empty === 1'b0 && full === 1'b0, "flags with 8 words");
        drain; end_test;

        begin_test(4, "multiple sequential reads");
        sys_reset; write_n(8); wait_rd(6); read_n(8); wait_rd(2);
        check(occ == 0, "all 8 compared");
        check(empty === 1'b1, "empty after 8 reads");
        end_test;

        begin_test(5, "full detection");
        sys_reset; fill; wait_wr(3);
        check(full === 1'b1, "full flag at DEPTH");
        check(occ == DEPTH, "occupancy == DEPTH");
        drain; end_test;

        begin_test(6, "empty detection");
        sys_reset; write_n(4); drain;
        check(empty === 1'b1, "empty after drain");
        end_test;

        begin_test(7, "write attempt while full");
        sys_reset; fill; base = n_wr_acc;
        wr_prob = 100; wait_wr(20); wr_prob = 0; wait_wr(2);
        check(n_wr_acc == base, "no write accepted while full");
        check(occ == DEPTH, "contents intact");
        drain; end_test;

        begin_test(8, "read attempt while empty");
        sys_reset; base = n_rd_acc;
        rd_prob = 100; wait_rd(20); rd_prob = 0; wait_rd(2);
        check(n_rd_acc == base, "no read accepted while empty");
        end_test;

        begin_test(9, "recovery after full");
        sys_reset; fill; read_n(4); wait_wr(6);
        check(full === 1'b0, "full clears after reads");
        write_n(4); wait_wr(3);
        check(full === 1'b1, "full again after refill");
        drain; end_test;

        begin_test(10, "recovery after empty");
        sys_reset; write_n(3); wait_rd(6); read_n(3); wait_rd(3);
        check(empty === 1'b1, "empty reached");
        write_n(2); wait_rd(6); read_n(2); drain; end_test;
    end
endtask
