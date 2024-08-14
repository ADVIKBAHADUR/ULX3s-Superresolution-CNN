module superresolution #(
    parameter PIXEL_WIDTH = 24,
    parameter WEIGHT_ADDR_WIDTH = 18,
    parameter WIDTH = 320,
    parameter HEIGHT = 240
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
    // Parameters
    localparam TOTAL_LAYERS = 6; // Upsample + 5 Conv layers
    localparam MAX_CHANNELS = 12; // Maximum number of channels in any layer

    // Internal signals
    wire [9*PIXEL_WIDTH-1:0] layer_input;
    wire [MAX_CHANNELS*8-1:0] upsample_output;
    wire [8*9-1:0] conv1_output, conv2_output, conv3_output, conv4_output;
    wire [PIXEL_WIDTH-1:0] conv5_output;
    reg [2:0] current_layer;
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

    // Control signals for layers
    reg [TOTAL_LAYERS-1:0] start_conv;
    wire [TOTAL_LAYERS-1:0] conv_done;

    // Connect neighborhood to layer_input
    assign layer_input = neighborhood;

    // Upsample layer instance
    upsample_layer #(
        .IN_CHANNELS(3),
        .OUT_CHANNELS(12),
        .DATA_WIDTH(8),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
    ) upsample (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_in(layer_input),
        .load_weights(load_weights && current_layer == 0),
        .weight_addr(weight_addr),
        .start_conv(start_conv[0]),
        .pixel_out(upsample_output),
        .conv_done(conv_done[0]),
        .debug_leds()
    );

    // Convolutional layers
    conv_layer #(
        .IN_CHANNELS(12),
        .OUT_CHANNELS(9),
        .DATA_WIDTH(8),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
    ) conv1 (
        .clk(clk),
        .rst_n(rst_n),
        .load_weights(load_weights && current_layer == 1),
        .weight_addr(weight_addr),
        .start_conv(start_conv[1]),
        .pixel_in(upsample_output),
        .pixel_out(conv1_output),
        .conv_done(conv_done[1]),
        .debug_leds()
    );

    conv_layer #(
        .IN_CHANNELS(9),
        .OUT_CHANNELS(9),
        .DATA_WIDTH(8),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
    ) conv2 (
        .clk(clk),
        .rst_n(rst_n),
        .load_weights(load_weights && current_layer == 2),
        .weight_addr(weight_addr),
        .start_conv(start_conv[2]),
        .pixel_in(conv1_output),
        .pixel_out(conv2_output),
        .conv_done(conv_done[2]),
        .debug_leds()
    );

    conv_layer #(
        .IN_CHANNELS(9),
        .OUT_CHANNELS(9),
        .DATA_WIDTH(8),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
    ) conv3 (
        .clk(clk),
        .rst_n(rst_n),
        .load_weights(load_weights && current_layer == 3),
        .weight_addr(weight_addr),
        .start_conv(start_conv[3]),
        .pixel_in(conv2_output),
        .pixel_out(conv3_output),
        .conv_done(conv_done[3]),
        .debug_leds()
    );

    conv_layer #(
        .IN_CHANNELS(9),
        .OUT_CHANNELS(9),
        .DATA_WIDTH(8),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
    ) conv4 (
        .clk(clk),
        .rst_n(rst_n),
        .load_weights(load_weights && current_layer == 4),
        .weight_addr(weight_addr),
        .start_conv(start_conv[4]),
        .pixel_in(conv3_output),
        .pixel_out(conv4_output),
        .conv_done(conv_done[4]),
        .debug_leds()
    );

    conv_layer #(
        .IN_CHANNELS(9),
        .OUT_CHANNELS(3),
        .DATA_WIDTH(8),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
    ) conv5 (
        .clk(clk),
        .rst_n(rst_n),
        .load_weights(load_weights && current_layer == 5),
        .weight_addr(weight_addr),
        .start_conv(start_conv[5]),
        .pixel_in(conv4_output),
        .pixel_out(conv5_output),
        .conv_done(conv_done[5]),
        .debug_leds()
    );

    // ReLU activation
    wire [PIXEL_WIDTH-1:0] relu_output;
    relu relu_inst (
        .pixel_in(conv5_output),
        .pixel_out(relu_output)
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
            start_conv <= 0;
        end else begin
            debug_counter <= debug_counter + 1;
            
            case (state)
                IDLE: begin
                    layer_wait_counter <= 0;
                    layer_timeout <= 0;
                    start_conv <= 0;
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
                        start_conv[current_layer] <= 1;
                    end
                end

                PROCESS_LAYERS: begin
                    layer_wait_counter <= layer_wait_counter + 1;
                    
                    if (conv_done[current_layer]) begin
                        start_conv[current_layer] <= 0;
                        if (current_layer == TOTAL_LAYERS - 1) begin
                            pixel_out <= relu_output;
                            pixel_processed_counter <= pixel_processed_counter + 1;
                            if (pixel_processed_counter >= WIDTH * HEIGHT - 1) begin
                                state <= FINISH;
                            end else begin
                                current_layer <= 0;
                                start_conv[0] <= 1;
                            end
                        end else begin
                            current_layer <= current_layer + 1;
                            start_conv[current_layer + 1] <= 1;
                        end
                        layer_wait_counter <= 0;
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
            debug_leds[7] <= start_conv[0];
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
    parameter OUT_CHANNELS = 12, // 3 * (SCALE_FACTOR ** 2)
    parameter DATA_WIDTH = 8,
    parameter WEIGHT_ADDR_WIDTH = 20
)(
    input wire clk,
    input wire rst_n,
    input wire [9*IN_CHANNELS*DATA_WIDTH-1:0] pixel_in,
    input wire load_weights,
    input wire [WEIGHT_ADDR_WIDTH-1:0] weight_addr,
    input wire start_conv,
    output reg [OUT_CHANNELS*DATA_WIDTH-1:0] pixel_out,
    output reg conv_done,
    output reg [7:0] debug_leds
);
    // Local parameters
    localparam KERNEL_SIZE = 3;
    localparam BRAM_DEPTH = IN_CHANNELS * OUT_CHANNELS * KERNEL_SIZE * KERNEL_SIZE + OUT_CHANNELS;

    // Weight and bias memory
    reg [DATA_WIDTH-1:0] weight_bias_mem [0:BRAM_DEPTH-1];
    
    // Intermediate results
    reg signed [2*DATA_WIDTH+3:0] conv_result [0:OUT_CHANNELS-1];
    wire signed [DATA_WIDTH-1:0] bias [0:OUT_CHANNELS-1];
    
    // Counters and control signals
    reg [7:0] out_channel_count;
    reg [3:0] in_channel_count;
    reg [3:0] kernel_row, kernel_col;
    reg [2:0] state;
    
    // State machine states
    localparam IDLE = 3'd0, LOAD = 3'd1, CONV = 3'd2, FINISH = 3'd3;

    // Multiplication result
    wire signed [2*DATA_WIDTH-1:0] mult_result;
    reg signed [DATA_WIDTH-1:0] mult_a, mult_b;

    // Assign biases
    genvar i;
    generate
        for (i = 0; i < OUT_CHANNELS; i = i + 1) begin : bias_assign
            assign bias[i] = weight_bias_mem[IN_CHANNELS * OUT_CHANNELS * KERNEL_SIZE * KERNEL_SIZE + i];
        end
    endgenerate

    // Weight and bias loading logic
    always @(posedge clk) begin
        if (load_weights) begin
            weight_bias_mem[weight_addr] <= pixel_in[DATA_WIDTH-1:0];
        end
    end

    // Multiplication
    assign mult_result = mult_a * mult_b;

    // Main processing logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            out_channel_count <= 0;
            in_channel_count <= 0;
            kernel_row <= 0;
            kernel_col <= 0;
            conv_done <= 0;
            mult_a <= 0;
            mult_b <= 0;
            debug_leds <= 8'b0;
            for (int j = 0; j < OUT_CHANNELS; j = j + 1) begin
                conv_result[j] <= 0;
                pixel_out[j*DATA_WIDTH +: DATA_WIDTH] <= 0;
            end
        end else begin
            case (state)
                IDLE: begin
                    if (start_conv) begin
                        state <= LOAD;
                        out_channel_count <= 0;
                        in_channel_count <= 0;
                        kernel_row <= 0;
                        kernel_col <= 0;
                        conv_done <= 0;
                        for (int j = 0; j < OUT_CHANNELS; j = j + 1) begin
                            conv_result[j] <= 0;
                        end
                    end
                end

                LOAD: begin
                    mult_a <= weight_bias_mem[out_channel_count * IN_CHANNELS * KERNEL_SIZE * KERNEL_SIZE + 
                                              in_channel_count * KERNEL_SIZE * KERNEL_SIZE +
                                              kernel_row * KERNEL_SIZE +
                                              kernel_col];
                    mult_b <= pixel_in[(in_channel_count * KERNEL_SIZE * KERNEL_SIZE + 
                                        kernel_row * KERNEL_SIZE + 
                                        kernel_col) * DATA_WIDTH +: DATA_WIDTH];
                    state <= CONV;
                end

                CONV: begin
                    conv_result[out_channel_count] <= conv_result[out_channel_count] + mult_result;

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
                                    state <= LOAD;
                                end
                            end else begin
                                in_channel_count <= in_channel_count + 1;
                                state <= LOAD;
                            end
                        end else begin
                            kernel_row <= kernel_row + 1;
                            state <= LOAD;
                        end
                    end else begin
                        kernel_col <= kernel_col + 1;
                        state <= LOAD;
                    end
                end

                FINISH: begin
                    for (int j = 0; j < OUT_CHANNELS; j = j + 1) begin
                        // Apply bias and activation
                        if (conv_result[j] + {{(DATA_WIDTH+4){bias[j][DATA_WIDTH-1]}}, bias[j]} > {1'b0, {(DATA_WIDTH-1){1'b1}}}) begin
                            pixel_out[j*DATA_WIDTH +: DATA_WIDTH] <= {DATA_WIDTH{1'b1}};
                        end else if (conv_result[j] + {{(DATA_WIDTH+4){bias[j][DATA_WIDTH-1]}}, bias[j]} < {1'b1, {(DATA_WIDTH-1){1'b0}}}) begin
                            pixel_out[j*DATA_WIDTH +: DATA_WIDTH] <= {DATA_WIDTH{1'b0}};
                        end else begin
                            pixel_out[j*DATA_WIDTH +: DATA_WIDTH] <= conv_result[j][DATA_WIDTH-1:0] + bias[j];
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

module conv_layer #(
    parameter IN_CHANNELS = 3,
    parameter OUT_CHANNELS = 64,
    parameter KERNEL_SIZE = 3,
    parameter DATA_WIDTH = 8,
    parameter WEIGHT_ADDR_WIDTH = 20
)(
    input wire clk,
    input wire rst_n,
    input wire load_weights,
    input wire [WEIGHT_ADDR_WIDTH-1:0] weight_addr,
    input wire start_conv,
    input wire [KERNEL_SIZE*KERNEL_SIZE*IN_CHANNELS*DATA_WIDTH-1:0] pixel_in,
    output reg [OUT_CHANNELS*DATA_WIDTH-1:0] pixel_out,
    output reg conv_done,
    output reg [7:0] debug_leds
);
    localparam WEIGHT_MEM_DEPTH = IN_CHANNELS * OUT_CHANNELS * KERNEL_SIZE * KERNEL_SIZE;
    localparam BIAS_MEM_DEPTH = OUT_CHANNELS;
    localparam TOTAL_MEM_DEPTH = WEIGHT_MEM_DEPTH + BIAS_MEM_DEPTH;
    
    // BRAM for weights and biases
    reg [DATA_WIDTH-1:0] weight_bias_mem [0:TOTAL_MEM_DEPTH-1];
    reg [WEIGHT_ADDR_WIDTH-1:0] bram_addr;
    wire [DATA_WIDTH-1:0] bram_data_out;
    
    // Intermediate results
    reg signed [2*DATA_WIDTH+3:0] conv_result;
    
    // Counters
    reg [7:0] out_channel_count;
    reg [7:0] in_channel_count;
    reg [3:0] kernel_row, kernel_col;
    
    // State machine
    reg [2:0] state;
    localparam IDLE = 3'd0, LOAD = 3'd1, CONV = 3'd2, FINISH = 3'd3;

    // DSP block for multiplication
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

    // BRAM read/write logic
    always @(posedge clk) begin
        if (load_weights) begin
            weight_bias_mem[weight_addr] <= bram_data_out;
        end
    end

    assign bram_data_out = weight_bias_mem[bram_addr];

    // Main convolution logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            out_channel_count <= 0;
            in_channel_count <= 0;
            kernel_row <= 0;
            kernel_col <= 0;
            conv_done <= 0;
            conv_result <= 0;
            bram_addr <= 0;
            mult_a <= 0;
            mult_b <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (start_conv) begin
                        state <= LOAD;
                        out_channel_count <= 0;
                        in_channel_count <= 0;
                        kernel_row <= 0;
                        kernel_col <= 0;
                        conv_result <= 0;
                        bram_addr <= 0;
                    end
                end

                LOAD: begin
                    bram_addr <= out_channel_count * IN_CHANNELS * KERNEL_SIZE * KERNEL_SIZE +
                                 in_channel_count * KERNEL_SIZE * KERNEL_SIZE +
                                 kernel_row * KERNEL_SIZE +
                                 kernel_col;
                    state <= CONV;
                end

                CONV: begin
                    // Perform convolution
                    mult_a <= bram_data_out;
                    mult_b <= pixel_in[(kernel_row*KERNEL_SIZE*IN_CHANNELS + kernel_col*IN_CHANNELS + in_channel_count)*DATA_WIDTH +: DATA_WIDTH];
                    conv_result <= conv_result + mult_result;

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
                                    state <= LOAD;
                                end
                            end else begin
                                in_channel_count <= in_channel_count + 1;
                                state <= LOAD;
                            end
                        end else begin
                            kernel_row <= kernel_row + 1;
                            state <= LOAD;
                        end
                    end else begin
                        kernel_col <= kernel_col + 1;
                        state <= LOAD;
                    end
                end

                FINISH: begin
                    // Apply bias
                    bram_addr <= WEIGHT_MEM_DEPTH + out_channel_count;
                    conv_result <= conv_result + {{(DATA_WIDTH+4){bram_data_out[DATA_WIDTH-1]}}, bram_data_out};
                    
                    // Apply activation and store result
                    if (conv_result > {1'b0, {(DATA_WIDTH-1){1'b1}}}) begin
                        pixel_out[out_channel_count*DATA_WIDTH +: DATA_WIDTH] <= {DATA_WIDTH{1'b1}};
                    end else if (conv_result < {1'b1, {(DATA_WIDTH-1){1'b0}}}) begin
                        pixel_out[out_channel_count*DATA_WIDTH +: DATA_WIDTH] <= {DATA_WIDTH{1'b0}};
                    end else begin
                        pixel_out[out_channel_count*DATA_WIDTH +: DATA_WIDTH] <= conv_result[DATA_WIDTH-1:0];
                    end

                    if (out_channel_count == OUT_CHANNELS - 1) begin
                        conv_done <= 1;
                        state <= IDLE;
                    end else begin
                        out_channel_count <= out_channel_count + 1;
                        conv_result <= 0;
                        state <= LOAD;
                    end
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