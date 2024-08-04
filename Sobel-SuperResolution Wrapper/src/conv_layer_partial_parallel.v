module conv_core_partial_parallel(
    input clk,
    input reset,
    input [DATA_WIDTH-1:0] input_pixels[0:8][0:IN_CHANNELS-1], // 3x3 pixels for each input channel
    input [DATA_WIDTH-1:0] weights[0:8][0:IN_CHANNELS-1][0:PARTIAL_FILTERS-1], // Weights for 3 filters at a time
    input [DATA_WIDTH-1:0] bias[0:PARTIAL_FILTERS-1],              // Bias for the partial filters
    output reg [DATA_WIDTH-1:0] output_pixel[0:PARTIAL_FILTERS-1]  // Output pixels for partial filters
);
    parameter DATA_WIDTH = 8;
    parameter IN_CHANNELS = 9;
    parameter PARTIAL_FILTERS = 3;

    wire [DATA_WIDTH*2-1:0] mult_results[0:8][0:IN_CHANNELS-1][0:PARTIAL_FILTERS-1];
    reg [DATA_WIDTH*2-1:0] add_results[0:PARTIAL_FILTERS-1];
    reg [DATA_WIDTH-1:0] final_results[0:PARTIAL_FILTERS-1];

    genvar i, j, k;
    generate
        for (i = 0; i < PARTIAL_FILTERS; i = i + 1) begin : out_ch
            for (j = 0; j < 9; j = j + 1) begin : pixel
                for (k = 0; k < IN_CHANNELS; k = k + 1) begin : in_ch
                    assign mult_results[j][k][i] = input_pixels[j][k] * weights[j][k][i];
                end
            end
        end
    endgenerate

    generate
        for (i = 0; i < PARTIAL_FILTERS; i = i + 1) begin : out_ch_sum
            always @(posedge clk or posedge reset) begin
                if (reset) begin
                    add_results[i] <= 0;
                    output_pixel[i] <= 0;
                end else begin
                    add_results[i] = bias[i];
                    for (j = 0; j < 9; j = j + 1) begin
                        for (k = 0; k < IN_CHANNELS; k = k + 1) begin
                            add_results[i] = add_results[i] + mult_results[j][k][i];
                        end
                    end
                    final_results[i] = add_results[i][DATA_WIDTH*2-1:DATA_WIDTH];
                    output_pixel[i] <= final_results[i];
                end
            end
        end
    endgenerate
endmodule

