module superresolution(
    input wire clk,
    input wire rst_n,
    input wire [23:0] pixel_in,
    input wire start_process,
    input wire [10:0] x_in,
    input wire [10:0] y_in,
    output reg [23:0] pixel_out,
    output reg process_done
);
    // Parameters
    parameter DATA_WIDTH = 8;
    parameter WEIGHT_ADDR_WIDTH = 18;
    parameter WIDTH = 640;
    parameter HEIGHT = 480;
    parameter SCALE = 2;
    parameter OUT_WIDTH = WIDTH * SCALE;
    parameter OUT_HEIGHT = HEIGHT * SCALE;
    parameter BUFFER_LINES = 3;

    // Internal signals
    wire [23:0] upsample_out, conv1_out, conv2_out, conv3_out, conv4_out, conv5_out, relu_out;
    reg [WEIGHT_ADDR_WIDTH-1:0] weight_addr;
    reg load_weights;
    reg [2:0] current_layer;
    reg [8:0] weight_counter;

    // Line buffers and processing state
    reg [23:0] line_buffer [0:BUFFER_LINES-1][0:WIDTH-1];
    reg [1:0] current_line;
    reg [9:0] proc_x;
    reg [8:0] proc_y;
    reg [9:0] input_x;
    reg [8:0] input_y;
    reg processing;

    // State machine states
    localparam IDLE = 3'd0, LOAD_WEIGHTS = 3'd1, PROCESS_FRAME = 3'd2;
    reg [1:0] state;

    // Debug signals
    reg [7:0] debug_state;
    reg [7:0] debug_weight;
    reg [7:0] debug_pattern;

    // Instantiate your modules here
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

    // Function to convert a 4-bit value to a 24-bit color
    function [23:0] value_to_color;
        input [3:0] value;
        begin
            case(value)
                4'h0: value_to_color = 24'hFFFFFF; // White
                4'h1: value_to_color = 24'hFF0000; // Red
                4'h2: value_to_color = 24'h00FF00; // Green
                4'h3: value_to_color = 24'h0000FF; // Blue
                4'h4: value_to_color = 24'hFFFF00; // Yellow
                4'h5: value_to_color = 24'h00FFFF; // Cyan
                4'h6: value_to_color = 24'hFF00FF; // Magenta
                4'h7: value_to_color = 24'h800000; // Dark Red
                4'h8: value_to_color = 24'h008000; // Dark Green
                4'h9: value_to_color = 24'h000080; // Dark Blue
                4'hA: value_to_color = 24'h808000; // Olive
                4'hB: value_to_color = 24'h008080; // Teal
                4'hC: value_to_color = 24'h800080; // Purple
                4'hD: value_to_color = 24'h808080; // Gray
                4'hE: value_to_color = 24'h400000; // Maroon
                4'hF: value_to_color = 24'h000000; // Black
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            current_layer <= 0;
            weight_addr <= 0;
            load_weights <= 0;
            weight_counter <= 0;
            current_line <= 0;
            proc_x <= 0;
            proc_y <= 0;
            input_x <= 0;
            input_y <= 0;
            processing <= 0;
            process_done <= 0;
            pixel_out <= 0;
            debug_state <= 0;
            debug_weight <= 0;
            debug_pattern <= 0;
        end else begin
            case (state)
                IDLE: begin
                    debug_state <= 8'd0;
                    if (start_process) begin
                        state <= LOAD_WEIGHTS;
                        current_layer <= 0;
                        weight_addr <= 0;
                        load_weights <= 1;
                        weight_counter <= 0;
                        current_line <= 0;
                        proc_x <= 0;
                        proc_y <= 0;
                        input_x <= 0;
                        input_y <= 0;
                        processing <= 0;
                        process_done <= 0;
                    end
                end
                LOAD_WEIGHTS: begin
                    debug_state <= 8'd1;
                    weight_addr <= weight_addr + 1;
                    weight_counter <= weight_counter + 1;
                    debug_weight <= weight_addr[7:0]; // Use lower 8 bits of weight_addr for debug
                    if (weight_counter == 255) begin  // Adjust based on your layer sizes
                        if (current_layer == 5) begin
                            state <= PROCESS_FRAME;
                            load_weights <= 0;
                            processing <= 1;
                        end else begin
                            current_layer <= current_layer + 1;
                            weight_counter <= 0;
                        end
                    end
                end
                PROCESS_FRAME: begin
                    debug_state <= 8'd2;
                    // Store input pixel in line buffer
                    line_buffer[current_line][input_x] <= pixel_in;

                    if (processing && input_x > 1 && input_y > 1) begin
                        // For debugging, increment pattern instead of actual processing
                        debug_pattern <= debug_pattern + 1;

                        // Move to next pixel
                        if (proc_x < WIDTH - 2) begin
                            proc_x <= proc_x + 1;
                        end else begin
                            proc_x <= 0;
                            if (proc_y < HEIGHT - 2) begin
                                proc_y <= proc_y + 1;
                                current_line <= (current_line + 1) % BUFFER_LINES;
                            end else begin
                                state <= IDLE;
                                process_done <= 1;
                            end
                        end
                    end

                    // Move to next input pixel
                    if (input_x < WIDTH - 1) begin
                        input_x <= input_x + 1;
                    end else begin
                        input_x <= 0;
                        if (input_y < HEIGHT - 1) begin
                            input_y <= input_y + 1;
                            current_line <= (current_line + 1) % BUFFER_LINES;
                        end else begin
                            input_y <= 0;
                        end
                    end
                end
            endcase

            // Overlay debug information
            if (y_in < 16) begin
                if (x_in < 16) begin
                    // Display debug_state in top-left corner
                    pixel_out <= value_to_color(debug_state[3:0]);
                end else if (x_in < 32) begin
                    // Display upper 4 bits of debug_weight
                    pixel_out <= value_to_color(debug_weight[7:4]);
                end else if (x_in < 48) begin
                    // Display lower 4 bits of debug_weight
                    pixel_out <= value_to_color(debug_weight[3:0]);
                end else if (x_in < 64) begin
                    // Display debug_pattern
                    pixel_out <= value_to_color(debug_pattern[3:0]);
                end
            end else if (processing) begin
                // Output debug pattern during processing
                pixel_out <= {debug_pattern, debug_pattern, debug_pattern};
            end else begin
                // Pass through input pixel when not processing
                pixel_out <= pixel_in;
            end
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
    // Weights and biases
    reg signed [DATA_WIDTH-1:0] weights [0:OUT_CHANNELS-1][0:IN_CHANNELS-1][0:KERNEL_SIZE-1][0:KERNEL_SIZE-1];
    reg signed [DATA_WIDTH-1:0] biases [0:OUT_CHANNELS-1];
    
    // Intermediate results
    reg signed [2*DATA_WIDTH-1:0] conv_result [0:OUT_CHANNELS-1];
    
    integer i, j, k, l, m;

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

    // Parallel convolution logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < OUT_CHANNELS; i = i + 1) begin
                conv_result[i] <= 0;
                pixel_out[i*DATA_WIDTH +: DATA_WIDTH] <= 0;
            end
        end else if (!load_weights) begin
            for (i = 0; i < OUT_CHANNELS; i = i + 1) begin
                conv_result[i] <= 0;
                for (j = 0; j < IN_CHANNELS; j = j + 1) begin
                    for (k = 0; k < KERNEL_SIZE; k = k + 1) begin
                        for (l = 0; l < KERNEL_SIZE; l = l + 1) begin
                            conv_result[i] <= conv_result[i] + 
                                $signed(pixel_in[j*DATA_WIDTH +: DATA_WIDTH]) * 
                                $signed(weights[i][j][k][l]);
                        end
                    end
                end
                // Add bias and apply activation
                if (conv_result[i] + biases[i] > {1'b0, {(DATA_WIDTH-1){1'b1}}}) begin
                    pixel_out[i*DATA_WIDTH +: DATA_WIDTH] <= {DATA_WIDTH{1'b1}};
                end else if (conv_result[i] + biases[i] < {1'b1, {(DATA_WIDTH-1){1'b0}}}) begin
                    pixel_out[i*DATA_WIDTH +: DATA_WIDTH] <= {DATA_WIDTH{1'b0}};
                end else begin
                    pixel_out[i*DATA_WIDTH +: DATA_WIDTH] <= conv_result[i][DATA_WIDTH-1:0] + biases[i];
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