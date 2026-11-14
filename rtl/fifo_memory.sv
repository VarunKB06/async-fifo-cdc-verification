// Simple dual-port storage: write on wr_clk, asynchronous (combinational) read.
// Content of unwritten locations is undefined; dout is only meaningful while a read is accepted.
module fifo_memory #(
    parameter int DATA_WIDTH = 8,
    parameter int ADDR_WIDTH = 4
) (
    input  logic                  wr_clk,
    input  logic                  wr_we,     // accepted write
    input  logic [ADDR_WIDTH-1:0] waddr,
    input  logic [DATA_WIDTH-1:0] din,
    input  logic [ADDR_WIDTH-1:0] raddr,
    output logic [DATA_WIDTH-1:0] dout
);
    logic [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];

    always_ff @(posedge wr_clk)
        if (wr_we) mem[waddr] <= din;

    assign dout = mem[raddr];
endmodule
