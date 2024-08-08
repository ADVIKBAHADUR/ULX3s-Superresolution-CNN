module superresolution #(
    parameter PIXEL_WIDTH = 24,
    parameter WEIGHT_ADDR_WIDTH = 18,
    parameter PARALLEL_MULTS = 5
) (
    input wire clk,
    input wire rst_n,
    input wire [8:0] bram_addr,
    input wire start_process,
    input wire [9:0] x_in,
    input wire [9:0] y_in,
    output reg [PIXEL_WIDTH-1:0] pixel_out,
    output reg process_done
);
    // Parameters
    localparam CONV_LAYERS = 5;
    localparam MAX_CHANNELS = 12; // Maximum number of channels in any layer

    // State machine states
    localparam IDLE = 3'd0, LOAD_WEIGHTS = 3'd1, PROCESS_UPSAMPLE = 3'd2, 
               PROCESS_CONV = 3'd3, WAIT_CONV = 3'd4, FINISH = 3'd5;

    // Internal signals
    reg [PIXEL_WIDTH-1:0] neighborhood_bram [0:8];
    wire [PIXEL_WIDTH-1:0] layer_input [0:8];
    wire [MAX_CHANNELS*8-1:0] layer_output [0:CONV_LAYERS];
    reg [2:0] current_layer;
    reg [WEIGHT_ADDR_WIDTH-1:0] weight_addr;
    reg load_weights;
    reg [2:0] state;
    reg [MAX_CHANNELS*8-1:0] intermediate_bram [0:8];
    reg [3:0] bram_write_addr, bram_read_addr;
    reg start_conv;
    wire conv_done;

    // Next state and output signals
    reg [2:0] next_state;
    reg [2:0] next_current_layer;
    reg [WEIGHT_ADDR_WIDTH-1:0] next_weight_addr;
    reg next_load_weights;
    reg next_process_done;
    reg [3:0] next_bram_write_addr, next_bram_read_addr;
    reg next_start_conv;

    // Read 3x3 neighborhood from BRAM
    genvar n;
    generate
        for (n = 0; n < 9; n = n + 1) begin : neighborhood_read
            assign layer_input[n] = neighborhood_bram[bram_addr + n];
        end
    endgenerate

    // Instantiate your layer modules here
    upsample_layer #(
        .IN_CHANNELS(3),
        .OUT_CHANNELS(12),
        .DATA_WIDTH(8),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
    ) upsample (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_in(layer_input[4]), // Center pixel
        .load_weights(load_weights && current_layer == 0),
        .weight_addr(weight_addr),
        .pixel_out(layer_output[0])
    );

    genvar i;
    generate
        for (i = 1; i <= CONV_LAYERS; i = i + 1) begin : conv_layers
            conv_layer #(
                .IN_CHANNELS(i == 1 ? 12 : 9),
                .OUT_CHANNELS(i == CONV_LAYERS ? 3 : 9),
                .DATA_WIDTH(8),
                .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH),
                .PARALLEL_MULTS(PARALLEL_MULTS)
            ) conv (
                .clk(clk),
                .rst_n(rst_n),
                .bram_addr(bram_read_addr),
                .load_weights(load_weights && current_layer == i),
                .weight_addr(weight_addr),
                .start_conv(start_conv && current_layer == i),
                .pixel_out(layer_output[i]),
                .conv_done(conv_done)
            );
        end
    endgenerate

    // Sequential logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            current_layer <= 0;
            weight_addr <= 0;
            load_weights <= 0;
            process_done <= 0;
            pixel_out <= 0;
            bram_write_addr <= 0;
            bram_read_addr <= 0;
            start_conv <= 0;
        end else begin
            state <= next_state;
            current_layer <= next_current_layer;
            weight_addr <= next_weight_addr;
            load_weights <= next_load_weights;
            process_done <= next_process_done;
            bram_write_addr <= next_bram_write_addr;
            bram_read_addr <= next_bram_read_addr;
            start_conv <= next_start_conv;
        end
    end

    // Combinational logic
    always @* begin
        next_state = state;
        next_current_layer = current_layer;
        next_weight_addr = weight_addr;
        next_load_weights = load_weights;
        next_process_done = process_done;
        next_bram_write_addr = bram_write_addr;
        next_bram_read_addr = bram_read_addr;
        next_start_conv = start_conv;

        case (state)
            IDLE: begin
                if (start_process) begin
                    next_state = LOAD_WEIGHTS;
                    next_current_layer = 0;
                    next_weight_addr = 0;
                    next_load_weights = 1;
                    next_process_done = 0;
                end
            end

            LOAD_WEIGHTS: begin
                next_weight_addr = weight_addr + 1;
                if (weight_addr == (current_layer == 0 ? 435 : 328)) begin
                    if (current_layer == CONV_LAYERS) begin
                        next_state = PROCESS_UPSAMPLE;
                        next_load_weights = 0;
                        next_current_layer = 0;
                    end else begin
                        next_current_layer = current_layer + 1;
                        next_weight_addr = 0;
                    end
                end
            end

            PROCESS_UPSAMPLE: begin
                next_state = PROCESS_CONV;
                next_current_layer = 1;
                next_bram_write_addr = 0;
                // Store upsample result in BRAM
                intermediate_bram[bram_write_addr] = layer_output[0];
                next_bram_write_addr = bram_write_addr + 1;
            end

            PROCESS_CONV: begin
                next_start_conv = 1;
                next_state = WAIT_CONV;
            end

            WAIT_CONV: begin
                next_start_conv = 0;
                if (conv_done) begin
                    // Store conv result in BRAM
                    intermediate_bram[bram_write_addr] = layer_output[current_layer];
                    next_bram_write_addr = bram_write_addr + 1;
                    next_bram_read_addr = bram_write_addr - 8;
                    if (current_layer < CONV_LAYERS) begin
                        next_current_layer = current_layer + 1;
                        next_state = PROCESS_CONV;
                    end else begin
                        next_state = FINISH;
                    end
                end
            end

            FINISH: begin
                pixel_out = layer_output[CONV_LAYERS][23:0];
                next_process_done = 1;
                next_state = IDLE;
            end
        endcase
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
    output reg [OUT_CHANNELS*DATA_WIDTH-1:0] pixel_out
);
    wire [DATA_WIDTH-1:0] weight;
    reg [2*DATA_WIDTH-1:0] conv_result [0:OUT_CHANNELS-1];
    reg [DATA_WIDTH-1:0] bias [0:OUT_CHANNELS-1];
    integer i, j;

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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < OUT_CHANNELS; i = i + 1) begin
                conv_result[i] <= 0;
                bias[i] <= 0;
                pixel_out[i*DATA_WIDTH +: DATA_WIDTH] <= 0;
            end
        end else begin
            if (load_weights) begin
                if (weight_addr < IN_CHANNELS * OUT_CHANNELS * 9) begin
                    for (i = 0; i < IN_CHANNELS; i = i + 1) begin
                        conv_result[(weight_addr/9) % OUT_CHANNELS] <= conv_result[(weight_addr/9) % OUT_CHANNELS] + 
                                                                       pixel_in[i*DATA_WIDTH +: DATA_WIDTH] * $signed(weight);
                    end
                end else begin
                    bias[weight_addr % OUT_CHANNELS] <= weight;
                end
            end else begin
                for (i = 0; i < OUT_CHANNELS; i = i + 1) begin
                    pixel_out[i*DATA_WIDTH +: DATA_WIDTH] <= 
                        (conv_result[i][2*DATA_WIDTH-1] ? 0 : 
                        (|conv_result[i][2*DATA_WIDTH-2:DATA_WIDTH] ? {DATA_WIDTH{1'b1}} : 
                        conv_result[i][DATA_WIDTH-1:0])) + bias[i];
                    conv_result[i] <= 0;
                end
            end
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
    output reg conv_done
);
    // BRAM for 3x3 neighborhood
    reg [IN_CHANNELS*DATA_WIDTH-1:0] neighborhood_bram [0:8];
    wire [IN_CHANNELS*DATA_WIDTH-1:0] pixel_in [0:8];

    // Weights and biases
    reg signed [DATA_WIDTH-1:0] weights [0:OUT_CHANNELS-1][0:IN_CHANNELS-1][0:KERNEL_SIZE-1][0:KERNEL_SIZE-1];
    reg signed [DATA_WIDTH-1:0] biases [0:OUT_CHANNELS-1];
    
    // Intermediate results
    reg signed [2*DATA_WIDTH+3:0] conv_result [0:OUT_CHANNELS-1];
    
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
        end
    end

    // Combinational logic
    reg signed [2*DATA_WIDTH+3:0] next_conv_result [0:OUT_CHANNELS-1];
    reg next_conv_done;

    always @* begin
        next_state = state;
        next_out_channel_count = out_channel_count;
        next_in_channel_count = in_channel_count;
        next_kernel_count = kernel_count;
        next_conv_done = conv_done;
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
                    next_conv_done = 0;
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
                next_conv_done = 1;
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