module superresolution #(
    parameter PIXEL_WIDTH = 24,
    parameter WEIGHT_ADDR_WIDTH = 18,
    parameter WIDTH = 320,
    parameter HEIGHT = 240
) (
    input wire clk,
    input wire rst_n,
    input wire [8:0] bram_addr,
    input wire start_process,
    input wire [9:0] x_in,
    input wire [9:0] y_in,
    output reg [PIXEL_WIDTH-1:0] pixel_out,
    output reg process_done,
    output reg [7:0] debug_leds
);
    // Parameters
    localparam CONV_LAYERS = 5;
    localparam MAX_CHANNELS = 12; // Maximum number of channels in any layer

    // Internal signals
    reg [PIXEL_WIDTH-1:0] neighborhood_bram [0:8];
    wire [PIXEL_WIDTH-1:0] layer_input [0:8];
    wire [MAX_CHANNELS*8-1:0] upsample_output;
    reg [2:0] current_layer;
    reg [WEIGHT_ADDR_WIDTH-1:0] weight_addr;
    reg load_weights;
    
    // State machine states
    localparam IDLE = 3'd0, LOAD_WEIGHTS = 3'd1, PROCESS_UPSAMPLE = 3'd2, FINISH = 3'd3;
    reg [2:0] state;

    // Debugging counters and flags
    reg [31:0] debug_counter;
    reg [31:0] upsample_wait_counter;
    reg [31:0] pixel_processed_counter;
    reg [31:0] weight_load_counter;
    reg upsample_timeout;
    wire [7:0] upsample_debug_leds;

    // Read 3x3 neighborhood from BRAM
    genvar n;
    generate
        for (n = 0; n < 9; n = n + 1) begin : neighborhood_read
            assign layer_input[n] = neighborhood_bram[bram_addr + n];
        end
    endgenerate

    // Upsample layer instance
    upsample_layer #(
        .IN_CHANNELS(3),
        .OUT_CHANNELS(12),
        .DATA_WIDTH(8),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
    ) upsample (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_in(layer_input[4]), // Center pixel
        .load_weights(load_weights),
        .weight_addr(weight_addr),
        .pixel_out(upsample_output),
        .debug_leds(upsample_debug_leds)
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
            upsample_wait_counter <= 0;
            pixel_processed_counter <= 0;
            weight_load_counter <= 0;
            upsample_timeout <= 0;
            debug_leds <= 8'b0;
        end else begin
            debug_counter <= debug_counter + 1;
            
            case (state)
                IDLE: begin
                    upsample_wait_counter <= 0;
                    upsample_timeout <= 0;
                    if (start_process) begin
                        state <= LOAD_WEIGHTS;
                        current_layer <= 0;
                        weight_addr <= 0;
                        load_weights <= 1;  // Start loading weights
                        process_done <= 0;
                        weight_load_counter <= 0;
                    end
                end

                LOAD_WEIGHTS: begin
                    weight_addr <= weight_addr + 1;
                    weight_load_counter <= weight_load_counter + 1;
                    if (weight_addr == 435) begin // Adjust this value based on your upsample layer size
                        state <= PROCESS_UPSAMPLE;
                        load_weights <= 0;  // Stop loading weights
                    end
                end

                PROCESS_UPSAMPLE: begin
                    upsample_wait_counter <= upsample_wait_counter + 1;
                    if (upsample_debug_leds[1]) begin // Assuming LED[1] indicates upsample completion
                        pixel_out <= upsample_output[23:0]; // Assuming 3 channel output
                        pixel_processed_counter <= pixel_processed_counter + 1;
                        if (pixel_processed_counter >= WIDTH * HEIGHT - 1) begin
                            state <= FINISH;
                        end
                        upsample_wait_counter <= 0;
                    end else if (upsample_wait_counter >= 1000000) begin // Timeout after about 10ms at 100MHz
                        upsample_timeout <= 1;
                        state <= IDLE;
                    end
                end

                FINISH: begin
                    process_done <= 1;
                    state <= IDLE;
                end
            endcase

            // Debug LED indicators
            debug_leds[0] <= (state == IDLE ? 0 : (state ==  LOAD_WEIGHTS ? 1 : (state == PROCESS_UPSAMPLE ? 0 : (state == FINISH))));
            debug_leds[1] <= (state == IDLE ? 0 : (state ==  LOAD_WEIGHTS ? 0 : (state == PROCESS_UPSAMPLE ? 1 : (state == FINISH))));
            debug_leds[2] <= process_done;
            debug_leds[3] <= upsample_debug_leds[1];
            debug_leds[4] <= upsample_timeout;
            debug_leds[5] <= load_weights;
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
    parameter WEIGHT_ADDR_WIDTH = 20,
    parameter PARALLEL_MULTS = 5
)(
    input wire clk,
    input wire rst_n,
    input wire [3:0] bram_addr,
    input wire load_weights,
    input wire [WEIGHT_ADDR_WIDTH-1:0] weight_addr,
    input wire start_conv,
    output reg [OUT_CHANNELS*DATA_WIDTH-1:0] pixel_out,
    output reg conv_done,
    output reg [7:0] debug_leds
);
    // BRAM for 3x3 neighborhood
    reg [IN_CHANNELS*DATA_WIDTH-1:0] neighborhood_bram [0:8];
    wire [IN_CHANNELS*DATA_WIDTH-1:0] pixel_in [0:8];

    // Weights and biases
    reg signed [DATA_WIDTH-1:0] weights [0:OUT_CHANNELS-1][0:IN_CHANNELS-1][0:KERNEL_SIZE-1][0:KERNEL_SIZE-1];
    reg signed [DATA_WIDTH-1:0] biases [0:OUT_CHANNELS-1];
    
    // Intermediate results
    reg signed [2*DATA_WIDTH+3:0] conv_result [0:OUT_CHANNELS-1];
    reg signed [2*DATA_WIDTH+3:0] next_conv_result [0:OUT_CHANNELS-1];
    
    // Counters for time-multiplexing
    reg [3:0] out_channel_count, next_out_channel_count;
    reg [3:0] in_channel_count, next_in_channel_count;
    reg [3:0] kernel_count, next_kernel_count;
    
    // State machine
    reg [2:0] state, next_state;
    localparam IDLE = 3'd0, CONV = 3'd1, FINISH = 3'd2;

    // Multiple multipliers
    reg signed [DATA_WIDTH-1:0] mult_a [0:PARALLEL_MULTS-1];
    reg signed [DATA_WIDTH-1:0] mult_b [0:PARALLEL_MULTS-1];
    wire signed [2*DATA_WIDTH-1:0] mult_result [0:PARALLEL_MULTS-1];

    // Debugging
    reg [31:0] conv_cycles;
    reg [31:0] idle_cycles;
    reg conv_timeout;

    genvar i;
    generate
        for (i = 0; i < PARALLEL_MULTS; i = i + 1) begin : mult_gen
            assign mult_result[i] = mult_a[i] * mult_b[i];
        end
    endgenerate

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

    // Read 3x3 neighborhood from BRAM
    genvar n;
    generate
        for (n = 0; n < 9; n = n + 1) begin : neighborhood_read
            assign pixel_in[n] = neighborhood_bram[bram_addr + n];
        end
    endgenerate

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

    // Sequential logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            out_channel_count <= 0;
            in_channel_count <= 0;
            kernel_count <= 0;
            conv_done <= 0;
            conv_cycles <= 0;
            idle_cycles <= 0;
            conv_timeout <= 0;
            // debug_leds <= 8'b0;
            for (j = 0; j < OUT_CHANNELS; j = j + 1) begin
                conv_result[j] <= 0;
                pixel_out[j*DATA_WIDTH +: DATA_WIDTH] <= 0;
            end
            for (j = 0; j < PARALLEL_MULTS; j = j + 1) begin
                mult_a[j] <= 0;
                mult_b[j] <= 0;
            end
        end else begin
            state <= next_state;
            out_channel_count <= next_out_channel_count;
            in_channel_count <= next_in_channel_count;
            kernel_count <= next_kernel_count;
            for (j = 0; j < OUT_CHANNELS; j = j + 1) begin
                conv_result[j] <= next_conv_result[j];
            end
            
            case (state)
                IDLE: idle_cycles <= idle_cycles + 1;
                CONV: conv_cycles <= conv_cycles + 1;
                default: begin
                    idle_cycles <= 0;
                    conv_cycles <= 0;
                end
            endcase

            if (conv_cycles > 1000000) begin // Timeout after about 10ms at 100MHz
                conv_timeout <= 1;
                state <= IDLE;
            end

            // Debug LED indicators
            debug_leds[2:0] <= state;
            debug_leds[3] <= start_conv;
            debug_leds[4] <= conv_done;
            debug_leds[5] <= load_weights;
            debug_leds[6] <= (out_channel_count == OUT_CHANNELS - 1);
            debug_leds[7] <= conv_timeout;
        end
    end

    // Combinational logic
    always @* begin
        next_state = state;
        next_out_channel_count = out_channel_count;
        next_in_channel_count = in_channel_count;
        next_kernel_count = kernel_count;
        conv_done = 0;
        for (j = 0; j < OUT_CHANNELS; j = j + 1) begin
            next_conv_result[j] = conv_result[j];
        end

        case (state)
            IDLE: begin
                if (start_conv) begin
                    next_state = CONV;
                    next_out_channel_count = 0;
                    next_in_channel_count = 0;
                    next_kernel_count = 0;
                    for (j = 0; j < OUT_CHANNELS; j = j + 1) begin
                        next_conv_result[j] = 0;
                    end
                end
            end

            CONV: begin
                for (j = 0; j < PARALLEL_MULTS; j = j + 1) begin
                    if (out_channel_count + j < OUT_CHANNELS) begin
                        mult_a[j] = weights[out_channel_count + j][in_channel_count][kernel_count/3][kernel_count%3];
                        mult_b[j] = pixel_in[kernel_count][in_channel_count*DATA_WIDTH +: DATA_WIDTH];
                        next_conv_result[out_channel_count + j] = conv_result[out_channel_count + j] + mult_result[j];
                    end
                end

                if (kernel_count == 8) begin
                    next_kernel_count = 0;
                    if (in_channel_count == IN_CHANNELS - 1) begin
                        next_in_channel_count = 0;
                        next_out_channel_count = out_channel_count + PARALLEL_MULTS;
                        if (out_channel_count + PARALLEL_MULTS >= OUT_CHANNELS) begin
                            next_state = FINISH;
                        end
                    end else begin
                        next_in_channel_count = in_channel_count + 1;
                    end
                end else begin
                    next_kernel_count = kernel_count + 1;
                end
            end

            FINISH: begin
                for (j = 0; j < OUT_CHANNELS; j = j + 1) begin
                    if (conv_result[j] + biases[j] > {1'b0, {(DATA_WIDTH-1){1'b1}}}) begin
                        pixel_out[j*DATA_WIDTH +: DATA_WIDTH] = {DATA_WIDTH{1'b1}};
                    end else if (conv_result[j] + biases[j] < {1'b1, {(DATA_WIDTH-1){1'b0}}}) begin
                        pixel_out[j*DATA_WIDTH +: DATA_WIDTH] = {DATA_WIDTH{1'b0}};
                    end else begin
                        pixel_out[j*DATA_WIDTH +: DATA_WIDTH] = conv_result[j][DATA_WIDTH-1:0] + biases[j];
                    end
                end
                conv_done = 1;
                next_state = IDLE;
            end
        endcase
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