module superresolution #(
    parameter PIXEL_WIDTH = 24,
    parameter WEIGHT_ADDR_WIDTH = 18,
    parameter WIDTH = 320,
    parameter HEIGHT = 240,
    parameter IN_CHANNELS = 3,
    parameter HIDDEN_CHANNELS = 64,
    parameter OUT_CHANNELS = 3,
    parameter KERNEL_SIZE = 3
) (
    input wire clk,
    input wire rst_n,
    input wire start_process,
    input wire [9:0] x_in,
    input wire [9:0] y_in,
    input wire [9*PIXEL_WIDTH-1:0] neighborhood,
    output reg [PIXEL_WIDTH-1:0] pixel_out,
    output reg process_done,
    output reg [7:0] debug_leds
);
    // Internal signals
    wire [HIDDEN_CHANNELS*PIXEL_WIDTH-1:0] conv1_output, conv2_output, conv3_output, conv4_output;
    wire [OUT_CHANNELS*PIXEL_WIDTH-1:0] conv5_output;
    reg [4:0] current_layer;
    reg [WEIGHT_ADDR_WIDTH-1:0] weight_addr;
    reg load_weights;
    
    // State machine states
    localparam IDLE = 3'd0, LOAD_WEIGHTS = 3'd1, PROCESS_LAYERS = 3'd2, FINISH = 3'd3;
    reg [2:0] state;

    // Debugging counters and flags
    reg [31:0] debug_counter;
    reg [31:0] layer_wait_counter;
    reg [31:0] pixel_processed_counter;
    reg [31:0] weight_load_counter;
    reg layer_timeout;

    // Convolutional layers
    conv_layer #(
        .IN_CHANNELS(IN_CHANNELS),
        .OUT_CHANNELS(HIDDEN_CHANNELS),
        .KERNEL_SIZE(KERNEL_SIZE),
        .DATA_WIDTH(PIXEL_WIDTH/3),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
    ) conv1 (
        .clk(clk),
        .rst_n(rst_n),
        .load_weights(load_weights && current_layer == 0),
        .weight_addr(weight_addr),
        .start_conv(state == PROCESS_LAYERS && current_layer == 0),
        .pixel_in(neighborhood),
        .pixel_out(conv1_output),
        .conv_done(),
        .debug_leds()
    );

    conv_layer #(
        .IN_CHANNELS(HIDDEN_CHANNELS),
        .OUT_CHANNELS(HIDDEN_CHANNELS),
        .KERNEL_SIZE(KERNEL_SIZE),
        .DATA_WIDTH(PIXEL_WIDTH/3),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
    ) conv2 (
        .clk(clk),
        .rst_n(rst_n),
        .load_weights(load_weights && current_layer == 1),
        .weight_addr(weight_addr),
        .start_conv(state == PROCESS_LAYERS && current_layer == 1),
        .pixel_in(conv1_output),
        .pixel_out(conv2_output),
        .conv_done(),
        .debug_leds()
    );

    conv_layer #(
        .IN_CHANNELS(HIDDEN_CHANNELS),
        .OUT_CHANNELS(HIDDEN_CHANNELS),
        .KERNEL_SIZE(KERNEL_SIZE),
        .DATA_WIDTH(PIXEL_WIDTH/3),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
    ) conv3 (
        .clk(clk),
        .rst_n(rst_n),
        .load_weights(load_weights && current_layer == 2),
        .weight_addr(weight_addr),
        .start_conv(state == PROCESS_LAYERS && current_layer == 2),
        .pixel_in(conv2_output),
        .pixel_out(conv3_output),
        .conv_done(),
        .debug_leds()
    );

    conv_layer #(
        .IN_CHANNELS(HIDDEN_CHANNELS),
        .OUT_CHANNELS(HIDDEN_CHANNELS),
        .KERNEL_SIZE(KERNEL_SIZE),
        .DATA_WIDTH(PIXEL_WIDTH/3),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
    ) conv4 (
        .clk(clk),
        .rst_n(rst_n),
        .load_weights(load_weights && current_layer == 3),
        .weight_addr(weight_addr),
        .start_conv(state == PROCESS_LAYERS && current_layer == 3),
        .pixel_in(conv3_output),
        .pixel_out(conv4_output),
        .conv_done(),
        .debug_leds()
    );

    conv_layer #(
        .IN_CHANNELS(HIDDEN_CHANNELS),
        .OUT_CHANNELS(OUT_CHANNELS),
        .KERNEL_SIZE(KERNEL_SIZE),
        .DATA_WIDTH(PIXEL_WIDTH/3),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
    ) conv5 (
        .clk(clk),
        .rst_n(rst_n),
        .load_weights(load_weights && current_layer == 4),
        .weight_addr(weight_addr),
        .start_conv(state == PROCESS_LAYERS && current_layer == 4),
        .pixel_in(conv4_output),
        .pixel_out(conv5_output),
        .conv_done(),
        .debug_leds()
    );

    // Sequential logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            current_layer <= 0;
            weight_addr <= 0;
            load_weights <= 0;
            process_done <= 0;
            pixel_out <= 0;
            debug_counter <= 0;
            layer_wait_counter <= 0;
            pixel_processed_counter <= 0;
            weight_load_counter <= 0;
            layer_timeout <= 0;
            debug_leds <= 8'b0;
        end else begin
            debug_counter <= debug_counter + 1;
            
            case (state)
                IDLE: begin
                    layer_wait_counter <= 0;
                    layer_timeout <= 0;
                    if (start_process) begin
                        state <= LOAD_WEIGHTS;
                        current_layer <= 0;
                        weight_addr <= 0;
                        load_weights <= 1;
                        process_done <= 0;
                        weight_load_counter <= 0;
                    end
                end

                LOAD_WEIGHTS: begin
                    weight_addr <= weight_addr + 1;
                    weight_load_counter <= weight_load_counter + 1;
                    if (weight_load_counter == 1000) begin // Adjust this value based on your total weight count
                        state <= PROCESS_LAYERS;
                        load_weights <= 0;
                    end
                end

                PROCESS_LAYERS: begin
                    layer_wait_counter <= layer_wait_counter + 1;
                    if (layer_wait_counter == 100) begin // Adjust this value based on your convolution latency
                        if (current_layer == 4) begin
                            pixel_out <= conv5_output;
                            pixel_processed_counter <= pixel_processed_counter + 1;
                            if (pixel_processed_counter >= WIDTH * HEIGHT - 1) begin
                                state <= FINISH;
                            end else begin
                                current_layer <= 0;
                                layer_wait_counter <= 0;
                            end
                        end else begin
                            current_layer <= current_layer + 1;
                            layer_wait_counter <= 0;
                        end
                    end

                    if (layer_wait_counter >= 1000000) begin // Timeout after about 10ms at 100MHz
                        layer_timeout <= 1;
                        state <= IDLE;
                    end
                end

                FINISH: begin
                    process_done <= 1;
                    state <= IDLE;
                end
            endcase

            // Debug LED indicators
            debug_leds[0] <= (state == IDLE);
            debug_leds[1] <= (state == LOAD_WEIGHTS);
            debug_leds[2] <= (state == PROCESS_LAYERS);
            debug_leds[3] <= (state == FINISH);
            debug_leds[4] <= process_done;
            debug_leds[5] <= layer_timeout;
            debug_leds[6] <= (pixel_processed_counter > 0);
            debug_leds[7] <= start_process;
        end
    end

endmodule

module weight_loader #(
    parameter ADDR_WIDTH = 20,
    parameter DATA_WIDTH = 8,
    parameter MEM_SIZE = 1048576  // Adjust this based on your model's total weights and biases
)(
    input wire clk,
    input wire rst_n,
    input wire load_weights,
    input wire [ADDR_WIDTH-1:0] addr,
    output reg [DATA_WIDTH-1:0] weight_out
);
    reg [DATA_WIDTH-1:0] weight_mem [0:MEM_SIZE-1];
    
    initial begin
        $readmemh("smallmodelweights.mem", weight_mem);
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weight_out <= 0;
        end else if (load_weights) begin
            weight_out <= weight_mem[addr];
        end
    end
endmodule

module upsample_layer #(
    parameter SCALE_FACTOR = 2,
    parameter IN_CHANNELS = 3,
    parameter OUT_CHANNELS = 3 * (SCALE_FACTOR ** 2),
    parameter DATA_WIDTH = 8,
    parameter WEIGHT_ADDR_WIDTH = 20
)(
    input wire clk,
    input wire rst_n,
    input wire [IN_CHANNELS*DATA_WIDTH-1:0] pixel_in,
    input wire load_weights,
    input wire [WEIGHT_ADDR_WIDTH-1:0] weight_addr,
    output reg [OUT_CHANNELS*DATA_WIDTH-1:0] pixel_out,
    output reg [7:0] debug_leds
);
    wire [DATA_WIDTH-1:0] weight;
    reg [2*DATA_WIDTH-1:0] conv_result [0:OUT_CHANNELS-1];
    reg [DATA_WIDTH-1:0] bias [0:OUT_CHANNELS-1];
    
    // Debugging signals
    reg [31:0] pixel_counter;
    reg [31:0] weight_counter;
    reg [31:0] conv_counter;
    reg pixelshuffle_done;
    reg conv_done;
    reg weights_loaded;

    weight_loader #(
        .ADDR_WIDTH(WEIGHT_ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_SIZE(IN_CHANNELS * OUT_CHANNELS * 9 + OUT_CHANNELS)  // 3x3 kernel + biases
    ) weight_loader_inst (
        .clk(clk),
        .rst_n(rst_n),
        .load_weights(load_weights),
        .addr(weight_addr),
        .weight_out(weight)
    );

    integer i, j;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < OUT_CHANNELS; i = i + 1) begin
                conv_result[i] <= 0;
                bias[i] <= 0;
                pixel_out[i*DATA_WIDTH +: DATA_WIDTH] <= 0;
            end
            pixel_counter <= 0;
            weight_counter <= 0;
            conv_counter <= 0;
            pixelshuffle_done <= 0;
            conv_done <= 0;
            weights_loaded <= 0;
            debug_leds <= 8'b0;
        end else begin
            if (load_weights) begin
                weight_counter <= weight_counter + 1;
                if (weight_addr < IN_CHANNELS * OUT_CHANNELS * 9) begin
                    for (i = 0; i < IN_CHANNELS; i = i + 1) begin
                        conv_result[(weight_addr/9) % OUT_CHANNELS] <= conv_result[(weight_addr/9) % OUT_CHANNELS] + 
                                                                       pixel_in[i*DATA_WIDTH +: DATA_WIDTH] * $signed(weight);
                    end
                end else begin
                    bias[weight_addr % OUT_CHANNELS] <= weight;
                end
                if (weight_counter == IN_CHANNELS * OUT_CHANNELS * 9 + OUT_CHANNELS - 1) begin
                    weights_loaded <= 1;
                end
            end else if (weights_loaded) begin
                pixel_counter <= pixel_counter + 1;
                conv_counter <= conv_counter + 1;
                for (i = 0; i < OUT_CHANNELS; i = i + 1) begin
                    pixel_out[i*DATA_WIDTH +: DATA_WIDTH] <= 
                        (conv_result[i][2*DATA_WIDTH-1] ? 0 : 
                        (|conv_result[i][2*DATA_WIDTH-2:DATA_WIDTH] ? {DATA_WIDTH{1'b1}} : 
                        conv_result[i][DATA_WIDTH-1:0])) + bias[i];
                    conv_result[i] <= 0;
                end
                conv_done <= 1;
                if (conv_counter % (SCALE_FACTOR * SCALE_FACTOR) == 0) begin
                    pixelshuffle_done <= 1;
                end else begin
                    pixelshuffle_done <= 0;
                end
            end

            // Debug LED indicators
            debug_leds[0] <= (pixel_counter > 0);  // Blinks when a pixel enters
            debug_leds[1] <= conv_done;            // Blinks when a pixel is processed
            debug_leds[2] <= pixelshuffle_done;    // Blinks when pixelshuffle completes
            debug_leds[3] <= load_weights;         // On during weight loading
            debug_leds[4] <= weights_loaded;       // On when weights are fully loaded
            debug_leds[5] <= (weight_counter > 0); // Blinks during weight loading
            debug_leds[7:6] <= pixel_counter[1:0]; // Shows lower 2 bits of pixel counter
        end
    end
endmodule

module conv_layer #(
    parameter IN_CHANNELS = 3,
    parameter OUT_CHANNELS = 9,
    parameter KERNEL_SIZE = 3,
    parameter DATA_WIDTH = 8,
    parameter WEIGHT_ADDR_WIDTH = 20
)(
    input wire clk,
    input wire rst_n,
    input wire load_weights,
    input wire [WEIGHT_ADDR_WIDTH-1:0] weight_addr,
    input wire start_conv,
    input wire [9*IN_CHANNELS*DATA_WIDTH-1:0] pixel_in,
    output reg [OUT_CHANNELS*DATA_WIDTH-1:0] pixel_out,
    output reg conv_done,
    output reg [7:0] debug_leds
);
    // Weights and biases
    reg signed [DATA_WIDTH-1:0] weights [0:OUT_CHANNELS-1][0:IN_CHANNELS-1][0:KERNEL_SIZE-1][0:KERNEL_SIZE-1];
    reg signed [DATA_WIDTH-1:0] biases [0:OUT_CHANNELS-1];
    
    // Intermediate results
    reg signed [2*DATA_WIDTH+3:0] conv_result [0:OUT_CHANNELS-1];
    
    // Counters
    reg [3:0] out_channel_count;
    reg [3:0] in_channel_count;
    reg [3:0] kernel_row, kernel_col;
    
    // State machine
    reg [2:0] state;
    localparam IDLE = 3'd0, CONV = 3'd1, FINISH = 3'd2;

    // Instantiate DSP blocks for multiplication
    wire signed [2*DATA_WIDTH-1:0] mult_result;
    reg signed [DATA_WIDTH-1:0] mult_a, mult_b;

    DSP_MULT #(
        .DATA_WIDTH(DATA_WIDTH)
    ) dsp_mult (
        .clk(clk),
        .a(mult_a),
        .b(mult_b),
        .p(mult_result)
    );

    // Weight loader instance
    wire [DATA_WIDTH-1:0] weight_data;
    weight_loader #(
        .ADDR_WIDTH(WEIGHT_ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_SIZE(IN_CHANNELS * OUT_CHANNELS * KERNEL_SIZE * KERNEL_SIZE + OUT_CHANNELS)
    ) weight_loader_inst (
        .clk(clk),
        .rst_n(rst_n),
        .load_weights(load_weights),
        .addr(weight_addr),
        .weight_out(weight_data)
    );

    // Weight and bias loading logic
    integer j, k, l, m;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (j = 0; j < OUT_CHANNELS; j = j + 1) begin
                for (k = 0; k < IN_CHANNELS; k = k + 1) begin
                    for (l = 0; l < KERNEL_SIZE; l = l + 1) begin
                        for (m = 0; m < KERNEL_SIZE; m = m + 1) begin
                            weights[j][k][l][m] <= 0;
                        end
                    end
                end
                biases[j] <= 0;
            end
        end else if (load_weights) begin
            if (weight_addr < IN_CHANNELS * OUT_CHANNELS * KERNEL_SIZE * KERNEL_SIZE) begin
                weights[weight_addr / (IN_CHANNELS * KERNEL_SIZE * KERNEL_SIZE)]
                       [(weight_addr / (KERNEL_SIZE * KERNEL_SIZE)) % IN_CHANNELS]
                       [(weight_addr / KERNEL_SIZE) % KERNEL_SIZE]
                       [weight_addr % KERNEL_SIZE] <= weight_data;
            end else begin
                biases[weight_addr - IN_CHANNELS * OUT_CHANNELS * KERNEL_SIZE * KERNEL_SIZE] <= weight_data;
            end
        end
    end

    // Main convolution logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            out_channel_count <= 0;
            in_channel_count <= 0;
            kernel_row <= 0;
            kernel_col <= 0;
            conv_done <= 0;
            for (j = 0; j < OUT_CHANNELS; j = j + 1) begin
                conv_result[j] <= 0;
                pixel_out[j*DATA_WIDTH +: DATA_WIDTH] <= 0;
            end
            mult_a <= 0;
            mult_b <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (start_conv) begin
                        state <= CONV;
                        out_channel_count <= 0;
                        in_channel_count <= 0;
                        kernel_row <= 0;
                        kernel_col <= 0;
                        for (j = 0; j < OUT_CHANNELS; j = j + 1) begin
                            conv_result[j] <= 0;
                        end
                    end
                end

                CONV: begin
                    // Perform convolution
                    mult_a <= weights[out_channel_count][in_channel_count][kernel_row][kernel_col];
                    mult_b <= pixel_in[(kernel_row*3 + kernel_col)*IN_CHANNELS*DATA_WIDTH + in_channel_count*DATA_WIDTH +: DATA_WIDTH];
                    conv_result[out_channel_count] <= conv_result[out_channel_count] + mult_result;

                    // Update counters
                    if (kernel_col == KERNEL_SIZE - 1) begin
                        kernel_col <= 0;
                        if (kernel_row == KERNEL_SIZE - 1) begin
                            kernel_row <= 0;
                            if (in_channel_count == IN_CHANNELS - 1) begin
                                in_channel_count <= 0;
                                if (out_channel_count == OUT_CHANNELS - 1) begin
                                    state <= FINISH;
                                end else begin
                                    out_channel_count <= out_channel_count + 1;
                                end
                            end else begin
                                in_channel_count <= in_channel_count + 1;
                            end
                        end else begin
                            kernel_row <= kernel_row + 1;
                        end
                    end else begin
                        kernel_col <= kernel_col + 1;
                    end
                end

                FINISH: begin
                    for (j = 0; j < OUT_CHANNELS; j = j + 1) begin
                        // Apply bias and activation
                        if (conv_result[j] + biases[j] > {1'b0, {(DATA_WIDTH-1){1'b1}}}) begin
                            pixel_out[j*DATA_WIDTH +: DATA_WIDTH] = {DATA_WIDTH{1'b1}};
                        end else if (conv_result[j] + biases[j] < {1'b1, {(DATA_WIDTH-1){1'b0}}}) begin
                            pixel_out[j*DATA_WIDTH +: DATA_WIDTH] = {DATA_WIDTH{1'b0}};
                        end else begin
                            pixel_out[j*DATA_WIDTH +: DATA_WIDTH] = conv_result[j][DATA_WIDTH-1:0] + biases[j];
                        end
                    end
                    conv_done <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end

    // Debug LED logic
    always @(posedge clk) begin
        debug_leds[2:0] <= state;
        debug_leds[3] <= start_conv;
        debug_leds[4] <= conv_done;
        debug_leds[5] <= load_weights;
        debug_leds[6] <= (out_channel_count == OUT_CHANNELS - 1);
        debug_leds[7] <= (state == CONV);
    end
endmodule

// DSP block for multiplication
module DSP_MULT #(
    parameter DATA_WIDTH = 8
)(
    input wire clk,
    input wire signed [DATA_WIDTH-1:0] a,
    input wire signed [DATA_WIDTH-1:0] b,
    output reg signed [2*DATA_WIDTH-1:0] p
);
    always @(posedge clk) begin
        p <= a * b;
    end
endmodule

module relu(
    input wire [23:0] pixel_in,
    output wire [23:0] pixel_out
);
    assign pixel_out[23:16] = (pixel_in[23:16] > 8'd0) ? pixel_in[23:16] : 8'd0;
    assign pixel_out[15:8]  = (pixel_in[15:8]  > 8'd0) ? pixel_in[15:8]  : 8'd0;
    assign pixel_out[7:0]   = (pixel_in[7:0]   > 8'd0) ? pixel_in[7:0]   : 8'd0;
endmodule   