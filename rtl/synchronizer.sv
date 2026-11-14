// N-stage flop synchronizer (async reset). Use ONLY for single-bit signals or Gray-coded buses.
module synchronizer #(
    parameter int W      = 1,
    parameter int STAGES = 2
) (
    input  logic         clk,
    input  logic         rst_n,
    input  logic [W-1:0] d,
    output logic [W-1:0] q
);
    initial if (STAGES < 2 || W < 1) begin
        $error("synchronizer: STAGES=%0d must be >=2 and W=%0d >=1", STAGES, W);
        $finish;
    end

    (* ASYNC_REG = "TRUE", keep = "true" *) logic [W-1:0] sync [STAGES];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < STAGES; i++) sync[i] <= '0;
        end else begin
            sync[0] <= d;
            for (int i = 1; i < STAGES; i++) sync[i] <= sync[i-1];
        end
    end

    assign q = sync[STAGES-1];
endmodule
