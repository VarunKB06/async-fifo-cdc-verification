// Parameterizable asynchronous FIFO (Gray-pointer architecture). Depth = 2**ADDR_WIDTH.
//
// Interface timing (see docs/architecture.md):
//   wr_ack   = wr_en & ~full   (combinational): the write is accepted at the next wr_clk edge.
//   rd_valid = rd_en & ~empty  (combinational): dout holds the popped word in the SAME cycle (first-word
//                              fall-through); the read is accepted at the next rd_clk edge.
//   dout is combinational from memory[read pointer]; it is don't-care when empty.
//   Synthesis note: the asynchronous (combinational) memory read maps to LUT-RAM/register-file/flop arrays.
//   It does NOT map to a synchronous-read block RAM; a BRAM-based variant needs a registered-read (non-FWFT)
//   interface or an output stage, which this design does not implement.
// Reset: wr_rst_n / rd_rst_n assert asynchronously; each must be released synchronously to its own clock
//        (external reset synchronizer). Both domains must be reset TOGETHER (system reset).
module async_fifo #(
    parameter int DATA_WIDTH  = 8,
    parameter int ADDR_WIDTH  = 4,
    parameter int SYNC_STAGES = 2
) (
    input  logic                  wr_clk,
    input  logic                  wr_rst_n,
    input  logic                  wr_en,
    input  logic [DATA_WIDTH-1:0] din,
    output logic                  full,
    output logic                  wr_ack,

    input  logic                  rd_clk,
    input  logic                  rd_rst_n,
    input  logic                  rd_en,
    output logic [DATA_WIDTH-1:0] dout,
    output logic                  empty,
    output logic                  rd_valid
);
    // ---- parameter restrictions (checked at time 0; simulation stops on violation)
    //   ADDR_WIDTH >= 2  : full detection inverts the two MSBs of the synchronized read Gray pointer
    //   SYNC_STAGES >= 2 : fewer stages give no metastability protection
    //   DATA_WIDTH >= 1
    initial begin
        if (ADDR_WIDTH < 2 || SYNC_STAGES < 2 || DATA_WIDTH < 1) begin
            $error("async_fifo: invalid parameters (ADDR_WIDTH=%0d must be >=2, SYNC_STAGES=%0d must be >=2, DATA_WIDTH=%0d must be >=1)",
                   ADDR_WIDTH, SYNC_STAGES, DATA_WIDTH);
            $finish;
        end
    end

    logic [ADDR_WIDTH:0]   wbin, wgray, wgray_next, rbin, rgray, rgray_next;
    logic [ADDR_WIDTH:0]   wgray_sync, rgray_sync;   // opposite-domain Gray pointers after synchronizer
    logic [ADDR_WIDTH-1:0] waddr, raddr;
    logic                  full_next, empty_next;

    assign wr_ack   = wr_en & ~full;
    assign rd_valid = rd_en & ~empty;

    write_pointer #(.ADDR_WIDTH(ADDR_WIDTH)) u_wptr (
        .wr_clk(wr_clk), .wr_rst_n(wr_rst_n), .wr_inc(wr_ack),
        .wbin(wbin), .wgray(wgray), .wgray_next(wgray_next), .waddr(waddr));

    read_pointer #(.ADDR_WIDTH(ADDR_WIDTH)) u_rptr (
        .rd_clk(rd_clk), .rd_rst_n(rd_rst_n), .rd_inc(rd_valid),
        .rbin(rbin), .rgray(rgray), .rgray_next(rgray_next), .raddr(raddr));

    // Gray pointers only cross clock domains
    synchronizer #(.W(ADDR_WIDTH+1), .STAGES(SYNC_STAGES)) u_sync_r2w (
        .clk(wr_clk), .rst_n(wr_rst_n), .d(rgray), .q(rgray_sync));
    synchronizer #(.W(ADDR_WIDTH+1), .STAGES(SYNC_STAGES)) u_sync_w2r (
        .clk(rd_clk), .rst_n(rd_rst_n), .d(wgray), .q(wgray_sync));

    full_empty_logic #(.ADDR_WIDTH(ADDR_WIDTH)) u_flags (
        .wgray_next(wgray_next), .rgray_sync(rgray_sync),
        .rgray_next(rgray_next), .wgray_sync(wgray_sync),
        .full_next(full_next), .empty_next(empty_next));

    always_ff @(posedge wr_clk or negedge wr_rst_n)
        if (!wr_rst_n) full <= 1'b0; else full <= full_next;

    always_ff @(posedge rd_clk or negedge rd_rst_n)
        if (!rd_rst_n) empty <= 1'b1; else empty <= empty_next;

    fifo_memory #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) u_mem (
        .wr_clk(wr_clk), .wr_we(wr_ack), .waddr(waddr), .din(din), .raddr(raddr), .dout(dout));
endmodule
