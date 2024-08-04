module neural_network_model(
    input wire clk,
    input wire reset,
    input wire [8:0] r_channel[0:2][0:2],
    input wire [8:0] g_channel[0:2][0:2],
    input wire [8:0] b_channel[0:2][0:2],
    output wire [7:0] output_r,
    output wire [7:0] output_g,
    output wire [7:0] output_b
);
    parameter DATA_WIDTH = 8;
    parameter IN_CHANNELS = 9;
    parameter OUT_CHANNELS = 9;

    wire [8:0] input_pixels[0:2][0:2][2:0];
    
    genvar i, j;
    generate
        for (i = 0; i < 3; i = i + 1) begin : gen_i
            for (j = 0; j < 3; j = j + 1) begin : gen_j
                assign input_pixels[i][j][0] = r_channel[i][j];
                assign input_pixels[i][j][1] = g_channel[i][j];
                assign input_pixels[i][j][2] = b_channel[i][j];
            end
        end
    endgenerate

    wire [DATA_WIDTH-1:0] conv1_output[0:OUT_CHANNELS-1];
    wire [DATA_WIDTH-1:0] conv2_output[0:OUT_CHANNELS-1];
    wire [DATA_WIDTH-1:0] conv3_output[0:OUT_CHANNELS-1];
    wire [DATA_WIDTH-1:0] conv4_output[0:OUT_CHANNELS-1];
    wire [DATA_WIDTH-1:0] conv5_output[0:2];

    conv_layer_partial_parallel #(
        .DATA_WIDTH(DATA_WIDTH),
        .IN_CHANNELS(3),
        .OUT_CHANNELS(9)
    ) conv1 (
        .clk(clk),
        .reset(reset),
        .input_pixels(input_pixels),
        .output_pixel(conv1_output),
        .weights(weights_conv1),
        .biases(biases_conv1)
    );

    conv_layer_partial_parallel #(
        .DATA_WIDTH(DATA_WIDTH),
        .IN_CHANNELS(9),
        .OUT_CHANNELS(9)
    ) conv2 (
        .clk(clk),
        .reset(reset),
        .input_pixels(conv1_output),
        .output_pixel(conv2_output),
        .weights(weights_conv2),
        .biases(biases_conv2)
    );

    conv_layer_partial_parallel #(
        .DATA_WIDTH(DATA_WIDTH),
        .IN_CHANNELS(9),
        .OUT_CHANNELS(9)
    ) conv3 (
        .clk(clk),
        .reset(reset),
        .input_pixels(conv2_output),
        .output_pixel(conv3_output),
        .weights(weights_conv3),
        .biases(biases_conv3)
    );

    conv_layer_partial_parallel #(
        .DATA_WIDTH(DATA_WIDTH),
        .IN_CHANNELS(9),
        .OUT_CHANNELS(9)
    ) conv4 (
        .clk(clk),
        .reset(reset),
        .input_pixels(conv3_output),
        .output_pixel(conv4_output),
        .weights(weights_conv4),
        .biases(biases_conv4)
    );

    conv_layer_partial_parallel #(
        .DATA_WIDTH(DATA_WIDTH),
        .IN_CHANNELS(9),
        .OUT_CHANNELS(3)
    ) conv5 (
        .clk(clk),
        .reset(reset),
        .input_pixels(conv4_output),
        .output_pixel(conv5_output),
        .weights(weights_conv5),
        .biases(biases_conv5)
    );

    assign output_r = conv5_output[0];
    assign output_g = conv5_output[1];
    assign output_b = conv5_output[2];
endmodule
