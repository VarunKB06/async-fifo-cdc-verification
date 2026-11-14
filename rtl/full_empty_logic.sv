// Combinational next-state flag logic (registered in async_fifo, each in its own clock domain).
//   full_next  : next write Gray pointer == synchronized read Gray pointer with the two MSBs inverted
//   empty_next : next read  Gray pointer == synchronized write Gray pointer
module full_empty_logic #(parameter int ADDR_WIDTH = 4) (
    input  logic [ADDR_WIDTH:0] wgray_next,
    input  logic [ADDR_WIDTH:0] rgray_sync,
    input  logic [ADDR_WIDTH:0] rgray_next,
    input  logic [ADDR_WIDTH:0] wgray_sync,
    output logic                full_next,
    output logic                empty_next
);
    initial if (ADDR_WIDTH < 2) begin $error("full_empty_logic: ADDR_WIDTH must be >= 2"); $finish; end

    assign full_next  = (wgray_next == {~rgray_sync[ADDR_WIDTH:ADDR_WIDTH-1], rgray_sync[ADDR_WIDTH-2:0]});
    assign empty_next = (rgray_next == wgray_sync);
endmodule
