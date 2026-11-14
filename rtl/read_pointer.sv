// Read-domain pointer. rd_inc must be the ACCEPTED read (rd_en & ~empty).
module read_pointer #(parameter int ADDR_WIDTH = 4) (
    input  logic                  rd_clk,
    input  logic                  rd_rst_n,
    input  logic                  rd_inc,
    output logic [ADDR_WIDTH:0]   rbin,
    output logic [ADDR_WIDTH:0]   rgray,
    output logic [ADDR_WIDTH:0]   rgray_next,
    output logic [ADDR_WIDTH-1:0] raddr
);
    logic [ADDR_WIDTH:0] rbin_next;

    assign rbin_next = rbin + {{ADDR_WIDTH{1'b0}}, rd_inc};
    gray_encoder #(.W(ADDR_WIDTH+1)) u_enc (.bin(rbin_next), .gray(rgray_next));

    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin rbin <= '0;        rgray <= '0;         end
        else           begin rbin <= rbin_next; rgray <= rgray_next; end
    end

    assign raddr = rbin[ADDR_WIDTH-1:0];
endmodule
