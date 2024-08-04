module superresolution(
    input wire clk,
    input wire rst_n,
    input wire [23:0] pixel_in,
    input wire start_process,
    output reg [23:0] pixel_out,
    output reg process_done
);
    // Parameters
    parameter DATA_WIDTH = 8;
    parameter WEIGHT_ADDR_WIDTH = 20;

    // Internal signals
    wire [23:0] upsample_out, conv1_out, conv2_out, conv3_out, conv4_out, conv5_out, relu_out;
    reg [WEIGHT_ADDR_WIDTH-1:0] weight_addr;
    reg load_weights;
    reg [2:0] current_layer;
    reg [9:0] weight_counter;

    // State machine states
    localparam IDLE = 3'd0, LOAD_WEIGHTS = 3'd1, PROCESS = 3'd2;
    reg [1:0] state;

    // Upsample layer
    upsample_layer #(
        .SCALE_FACTOR(2),
        .IN_CHANNELS(3),
        .OUT_CHANNELS(12),
        .DATA_WIDTH(DATA_WIDTH),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
    ) upsample (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_in(pixel_in),
        .load_weights(load_weights && current_layer == 3'd0),
        .weight_addr(weight_addr),
        .pixel_out(upsample_out)
    );

    // Convolution layers
    conv_layer #(.IN_CHANNELS(3), .OUT_CHANNELS(9)) conv1 (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_in(upsample_out),
        .load_weights(load_weights && current_layer == 3'd1),
        .weight_addr(weight_addr),
        .pixel_out(conv1_out)
    );

    conv_layer #(.IN_CHANNELS(9), .OUT_CHANNELS(9)) conv2 (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_in(conv1_out),
        .load_weights(load_weights && current_layer == 3'd2),
        .weight_addr(weight_addr),
        .pixel_out(conv2_out)
    );

    conv_layer #(.IN_CHANNELS(9), .OUT_CHANNELS(9)) conv3 (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_in(conv2_out),
        .load_weights(load_weights && current_layer == 3'd3),
        .weight_addr(weight_addr),
        .pixel_out(conv3_out)
    );

    conv_layer #(.IN_CHANNELS(9), .OUT_CHANNELS(9)) conv4 (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_in(conv3_out),
        .load_weights(load_weights && current_layer == 3'd4),
        .weight_addr(weight_addr),
        .pixel_out(conv4_out)
    );

    conv_layer #(.IN_CHANNELS(9), .OUT_CHANNELS(3)) conv5 (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_in(conv4_out),
        .load_weights(load_weights && current_layer == 3'd5),
        .weight_addr(weight_addr),
        .pixel_out(conv5_out)
    );

    relu relu_inst (
        .pixel_in(conv5_out),
        .pixel_out(relu_out)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            current_layer <= 0;
            weight_addr <= 0;
            load_weights <= 0;
            weight_counter <= 0;
            pixel_out <= 0;
            process_done <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (start_process) begin
                        state <= LOAD_WEIGHTS;
                        current_layer <= 0;
                        weight_addr <= 0;
                        load_weights <= 1;
                        weight_counter <= 0;
                        process_done <= 0;
                    end
                end
                LOAD_WEIGHTS: begin
                    weight_addr <= weight_addr + 1;
                    weight_counter <= weight_counter + 1;
                    if (weight_counter == 1023) begin  // Adjust this based on your layer sizes
                        if (current_layer == 5) begin
                            state <= PROCESS;
                            load_weights <= 0;
                        end else begin
                            current_layer <= current_layer + 1;
                            weight_counter <= 0;
                        end
                    end
                end
                PROCESS: begin
                    pixel_out <= relu_out;
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
        .MEM_SIZE(IN_CHANNELS * OUT_CHANNELS * KERNEL_SIZE * KERNEL_SIZE + OUT_CHANNELS)
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
                if (weight_addr < IN_CHANNELS * OUT_CHANNELS * KERNEL_SIZE * KERNEL_SIZE) begin
                    for (i = 0; i < IN_CHANNELS; i = i + 1) begin
                        conv_result[weight_addr % OUT_CHANNELS] <= conv_result[weight_addr % OUT_CHANNELS] + 
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

module relu(
    input wire [23:0] pixel_in,
    output wire [23:0] pixel_out
);
    assign pixel_out[23:16] = (pixel_in[23:16] > 8'd0) ? pixel_in[23:16] : 8'd0;
    assign pixel_out[15:8]  = (pixel_in[15:8]  > 8'd0) ? pixel_in[15:8]  : 8'd0;
    assign pixel_out[7:0]   = (pixel_in[7:0]   > 8'd0) ? pixel_in[7:0]   : 8'd0;
endmodule   