// Write-domain pointer: (ADDR_WIDTH+1)-bit binary + Gray. wr_inc must be the ACCEPTED write (wr_en & ~full).
module write_pointer #(parameter int ADDR_WIDTH = 4) (
    input  logic                  wr_clk,
    input  logic                  wr_rst_n,
    input  logic                  wr_inc,
    output logic [ADDR_WIDTH:0]   wbin,
    output logic [ADDR_WIDTH:0]   wgray,
    output logic [ADDR_WIDTH:0]   wgray_next,
    output logic [ADDR_WIDTH-1:0] waddr
);
    logic [ADDR_WIDTH:0] wbin_next;

    assign wbin_next = wbin + {{ADDR_WIDTH{1'b0}}, wr_inc};
    gray_encoder #(.W(ADDR_WIDTH+1)) u_enc (.bin(wbin_next), .gray(wgray_next));

    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin wbin <= '0;        wgray <= '0;         end
        else           begin wbin <= wbin_next; wgray <= wgray_next; end
    end

    assign waddr = wbin[ADDR_WIDTH-1:0];
endmodule
