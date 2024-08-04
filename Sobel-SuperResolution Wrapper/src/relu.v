module relu_activation(
    input clk,
    input reset,
    input [DATA_WIDTH-1:0] input_pixel[0:OUT_CHANNELS-1],
    output reg [DATA_WIDTH-1:0] output_pixel[0:OUT_CHANNELS-1]
);
    parameter DATA_WIDTH = 8;
    parameter OUT_CHANNELS = 9;

    genvar i;
    generate
        for (i = 0; i < OUT_CHANNELS; i = i + 1) begin : relu
            always @(posedge clk or posedge reset) begin
                if (reset) begin
                    output_pixel[i] <= 0;
                end else begin
                    output_pixel[i] <= (input_pixel[i][DATA_WIDTH-1]) ? 0 : input_pixel[i];
                end
            end
        end
    endgenerate
endmodule

