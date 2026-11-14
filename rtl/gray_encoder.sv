module gray_encoder #(parameter int W = 5) (
    input  logic [W-1:0] bin,
    output logic [W-1:0] gray
);
    assign gray = (bin >> 1) ^ bin;
endmodule
