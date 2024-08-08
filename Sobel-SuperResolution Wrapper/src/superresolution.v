module superresolution #(
    parameter PIXEL_WIDTH = 24,
    parameter WEIGHT_ADDR_WIDTH = 18
) (
    input wire clk,
    input wire rst_n,
    input wire [8:0] bram_addr, // Address for 3x3 neighborhood in BRAM
    input wire start_process,
    input wire [9:0] x_in,
    input wire [9:0] y_in,
    output reg [PIXEL_WIDTH-1:0] pixel_out,
    output reg process_done
);
    // Parameters
    localparam CONV_LAYERS = 5;
    localparam MAX_CHANNELS = 12; // Maximum number of channels in any layer

    // Internal signals
    reg [PIXEL_WIDTH-1:0] neighborhood_bram [0:8];
    wire [PIXEL_WIDTH-1:0] layer_input [0:8];
    wire [MAX_CHANNELS*8-1:0] layer_output [0:CONV_LAYERS];
    reg [2:0] current_layer;
    reg [WEIGHT_ADDR_WIDTH-1:0] weight_addr;
    reg load_weights;
    
    // State machine states
    localparam IDLE = 3'd0, LOAD_WEIGHTS = 3'd1, PROCESS_UPSAMPLE = 3'd2, 
               PROCESS_CONV = 3'd3, WAIT_CONV = 3'd4, FINISH = 3'd5;
    reg [2:0] state;

    // BRAM for storing intermediate results
    reg [MAX_CHANNELS*8-1:0] intermediate_bram [0:8];
    reg [3:0] bram_write_addr, bram_read_addr;

    // Signals for conv_layer control
    reg start_conv;
    wire conv_done;

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
                .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
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

    integer j;
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
            case (state)
                IDLE: begin
                    if (start_process) begin
                        state <= LOAD_WEIGHTS;
                        current_layer <= 0;
                        weight_addr <= 0;
                        load_weights <= 1;
                        process_done <= 0;
                    end
                end

                LOAD_WEIGHTS: begin
                    weight_addr <= weight_addr + 1;
                    if (weight_addr == (current_layer == 0 ? 435 : 328)) begin // Adjust these values based on your layer sizes
                        if (current_layer == CONV_LAYERS) begin
                            state <= PROCESS_UPSAMPLE;
                            load_weights <= 0;
                            current_layer <= 0;
                        end else begin
                            current_layer <= current_layer + 1;
                            weight_addr <= 0;
                        end
                    end
                end

                PROCESS_UPSAMPLE: begin
                    state <= PROCESS_CONV;
                    current_layer <= 1;
                    bram_write_addr <= 0;
                    // Store upsample result in BRAM
                    intermediate_bram[bram_write_addr] <= layer_output[0];
                    bram_write_addr <= bram_write_addr + 1;
                end

                PROCESS_CONV: begin
                    start_conv <= 1;
                    state <= WAIT_CONV;
                end

                WAIT_CONV: begin
                    start_conv <= 0;
                    if (conv_done) begin
                        // Store conv result in BRAM
                        intermediate_bram[bram_write_addr] <= layer_output[current_layer];
                        bram_write_addr <= bram_write_addr + 1;
                        bram_read_addr <= bram_write_addr - 8; // Set read address for next layer
                        if (current_layer < CONV_LAYERS) begin
                            current_layer <= current_layer + 1;
                            state <= PROCESS_CONV;
                        end else begin
                            state <= FINISH;
                        end
                    end
                end

                FINISH: begin
                    pixel_out <= layer_output[CONV_LAYERS][23:0]; // Assuming 3 channel output
                    process_done <= 1;
                    state <= IDLE;
                end
            endcase
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
    parameter WEIGHT_ADDR_WIDTH = 20
)(
    input wire clk,
    input wire rst_n,
    input wire [3:0] bram_addr, // Address for 3x3 neighborhood in BRAM
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
    reg [3:0] out_channel_count;
    reg [3:0] in_channel_count;
    reg [3:0] kernel_count;
    
    // State machine
    reg [2:0] state;
    localparam IDLE = 3'd0, CONV = 3'd1, FINISH = 3'd2;

    // Single multiplier
    reg signed [DATA_WIDTH-1:0] mult_a, mult_b;
    wire signed [2*DATA_WIDTH-1:0] mult_result;
    assign mult_result = mult_a * mult_b;

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
    integer i, j, k, l;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < OUT_CHANNELS; i = i + 1) begin
                for (j = 0; j < IN_CHANNELS; j = j + 1) begin
                    for (k = 0; k < KERNEL_SIZE; k = k + 1) begin
                        for (l = 0; l < KERNEL_SIZE; l = l + 1) begin
                            weights[i][j][k][l] <= 0;
                        end
                    end
                end
                biases[i] <= 0;
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

    // Convolution logic with time-multiplexing
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            out_channel_count <= 0;
            in_channel_count <= 0;
            kernel_count <= 0;
            conv_done <= 0;
            for (i = 0; i < OUT_CHANNELS; i = i + 1) begin
                conv_result[i] <= 0;
                pixel_out[i*DATA_WIDTH +: DATA_WIDTH] <= 0;
            end
        end else begin
            case (state)
                IDLE: begin
                    if (start_conv) begin
                        state <= CONV;
                        out_channel_count <= 0;
                        in_channel_count <= 0;
                        kernel_count <= 0;
                        conv_done <= 0;
                        for (i = 0; i < OUT_CHANNELS; i = i + 1) begin
                            conv_result[i] <= 0;
                        end
                    end
                end

                CONV: begin
                    mult_a <= weights[out_channel_count][in_channel_count][kernel_count/3][kernel_count%3];
                    mult_b <= pixel_in[kernel_count][in_channel_count*DATA_WIDTH +: DATA_WIDTH];
                    
                    conv_result[out_channel_count] <= conv_result[out_channel_count] + mult_result;

                    if (kernel_count == 8) begin
                        kernel_count <= 0;
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
                        kernel_count <= kernel_count + 1;
                    end
                end

                FINISH: begin
                    for (i = 0; i < OUT_CHANNELS; i = i + 1) begin
                        if (conv_result[i] + biases[i] > {1'b0, {(DATA_WIDTH-1){1'b1}}}) begin
                            pixel_out[i*DATA_WIDTH +: DATA_WIDTH] <= {DATA_WIDTH{1'b1}};
                        end else if (conv_result[i] + biases[i] < {1'b1, {(DATA_WIDTH-1){1'b0}}}) begin
                            pixel_out[i*DATA_WIDTH +: DATA_WIDTH] <= {DATA_WIDTH{1'b0}};
                        end else begin
                            pixel_out[i*DATA_WIDTH +: DATA_WIDTH] <= conv_result[i][DATA_WIDTH-1:0] + biases[i];
                        end
                    end
                    conv_done <= 1;
                    state <= IDLE;
                end
            endcase
        end
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