module superresolution #(
    parameter PIXEL_WIDTH = 16,
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
    input wire [9*PIXEL_WIDTH-1:0] neighborhood,
    output reg [PIXEL_WIDTH-1:0] pixel_out,
    output reg process_done,
    output reg pixel_done //,
    // output reg [7:0] debug_leds
);
    // Parameters
    localparam CONV_LAYERS = 5;
    localparam MAX_CHANNELS = 12;
    localparam KERNEL_SIZE = 3;
    localparam UPSAMPLE_IN_CHANNELS = 3;
    localparam UPSAMPLE_OUT_CHANNELS = 12;
    localparam UPSAMPLE_DATA_WIDTH = 16;
    localparam TOTAL_WEIGHTS = 3048; // Total number of weights to load

    // Internal signals
    wire [PIXEL_WIDTH-1:0] layer_input [0:8];
    wire [MAX_CHANNELS*8-1:0] upsample_output;
    wire [8*9-1:0] conv1_output, conv2_output, conv3_output, conv4_output;
    wire [PIXEL_WIDTH-1:0] conv5_output;
    reg [2:0] current_layer;
    reg [WEIGHT_ADDR_WIDTH-1:0] weight_addr;
    reg load_weights;

    // reg [7:0] debug_leds;
    
    // State machine states
    localparam IDLE = 3'd0, LOAD_WEIGHTS = 3'd1, PROCESS_LAYERS = 3'd2, FINISH = 3'd3;
    reg [2:0] state;
    reg [7:0] upsample_leds, conv_led, weight_load_led;

    // Debugging and control signals
    reg [31:0] debug_counter;
    reg [31:0] layer_wait_counter;
    reg [31:0] pixel_processed_counter;
    reg [31:0] weight_load_counter;
    reg layer_timeout;
    wire [CONV_LAYERS:0] layer_done;
    reg [CONV_LAYERS:0] start_layer;

    // Input and output color check
    reg input_has_color;
    reg output_has_color;

    // Weight loader
    wire [UPSAMPLE_DATA_WIDTH-1:0] weight_out;
    reg [WEIGHT_ADDR_WIDTH-1:0] chunk_start_addr;
    reg [5:0] chunk_counter; // Counter for chunks (0-63 for 32-word chunks)

    weight_loader #(
        .ADDR_WIDTH(WEIGHT_ADDR_WIDTH),
        .DATA_WIDTH(UPSAMPLE_DATA_WIDTH),
        .MEM_SIZE(TOTAL_WEIGHTS)
    ) weight_loader_inst (
        .clk(clk),
        .rst_n(rst_n),
        .load_weights(load_weights),
        .addr(weight_addr),
        .weight_out(weight_out)//,
        // .debug_leds(weight_load_led)
    );

    // Connect neighborhood to layer_input
    genvar n;
    generate
        for (n = 0; n < 9; n = n + 1) begin : neighborhood_connect
            assign layer_input[n] = neighborhood[n*PIXEL_WIDTH +: PIXEL_WIDTH];
        end
    endgenerate

    // Upsample layer instance
    upsample_layer #(
        .IN_CHANNELS(UPSAMPLE_IN_CHANNELS),
        .OUT_CHANNELS(UPSAMPLE_OUT_CHANNELS),
        .KERNEL_SIZE(KERNEL_SIZE),
        .DATA_WIDTH(UPSAMPLE_DATA_WIDTH),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
    ) upsample (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_in(neighborhood),
        .weight_in(weight_out),
        .load_weights(load_weights && current_layer == 0),
        .weight_addr(weight_addr),
        .start_conv(start_layer[0]),
        .pixel_out(upsample_output),
        .conv_done(layer_done[0])//,
        // .debug_leds(upsample_leds)
    );

        // Convolutional layers
    conv_layer #(
        .IN_CHANNELS(12),
        .OUT_CHANNELS(9),
        .KERNEL_SIZE(KERNEL_SIZE),
        .DATA_WIDTH(16),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
    ) conv1 (
        .clk(clk),
        .rst_n(rst_n),
        .weight_in(weight_out),
        .load_weights(load_weights && current_layer == 1),
        .weight_addr(weight_addr),
        .start_conv(start_layer[1]),
        .pixel_in(upsample_output),
        .pixel_out(conv1_output),
        .conv_done(layer_done[1])//,
        // .debug_leds(conv_led)
    );

    conv_layer #(
        .IN_CHANNELS(9),
        .OUT_CHANNELS(9),
        .KERNEL_SIZE(KERNEL_SIZE),
        .DATA_WIDTH(16),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
    ) conv2 (
        .clk(clk),
        .rst_n(rst_n),
        .weight_in(weight_out),
        .load_weights(load_weights && current_layer == 2),
        .weight_addr(weight_addr),
        .start_conv(start_layer[2]),
        .pixel_in(conv1_output),
        .pixel_out(conv2_output),
        .conv_done(layer_done[2])//,
        // .debug_leds()
    );

    conv_layer #(
        .IN_CHANNELS(9),
        .OUT_CHANNELS(9),
        .KERNEL_SIZE(KERNEL_SIZE),
        .DATA_WIDTH(16),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
    ) conv3 (
        .clk(clk),
        .rst_n(rst_n),
        .weight_in(weight_out),
        .load_weights(load_weights && current_layer == 3),
        .weight_addr(weight_addr),
        .start_conv(start_layer[3]),
        .pixel_in(conv2_output),
        .pixel_out(conv3_output),
        .conv_done(layer_done[3])//,
        // .debug_leds()
    );

    conv_layer #(
        .IN_CHANNELS(9),
        .OUT_CHANNELS(9),
        .KERNEL_SIZE(KERNEL_SIZE),
        .DATA_WIDTH(16),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
    ) conv4 (
        .clk(clk),
        .rst_n(rst_n),
        .weight_in(weight_out),
        .load_weights(load_weights && current_layer == 4),
        .weight_addr(weight_addr),
        .start_conv(start_layer[4]),
        .pixel_in(conv3_output),
        .pixel_out(conv4_output),
        .conv_done(layer_done[4])//,
        // .debug_leds()
    );

    conv_layer #(
        .IN_CHANNELS(9),
        .OUT_CHANNELS(3),
        .KERNEL_SIZE(KERNEL_SIZE),
        .DATA_WIDTH(16),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
    ) conv5 (
        .clk(clk),
        .rst_n(rst_n),
        .weight_in(weight_out),
        .load_weights(load_weights && current_layer == 5),
        .weight_addr(weight_addr),
        .start_conv(start_layer[5]),
        .pixel_in(conv4_output),
        .pixel_out(conv5_output),
        .conv_done(layer_done[5])//,
        // .debug_leds()
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
            chunk_start_addr <= 0;
            chunk_counter <= 0;
            load_weights <= 0;
            process_done <= 0;
            pixel_done <= 0;
            pixel_out <= 0;
            debug_counter <= 0;
            layer_wait_counter <= 0;
            pixel_processed_counter <= 0;
            weight_load_counter <= 0;
            layer_timeout <= 0;
            // debug_leds <= 8'b0;
            start_layer <= 0;
            input_has_color <= 0;
            output_has_color <= 0;
        end else begin
            debug_counter <= debug_counter + 1;
            
            case (state)
                IDLE: begin
                    layer_wait_counter <= 0;
                    layer_timeout <= 0;
                    pixel_done <= 0;
                    start_layer <= 0;
                    if (start_process) begin
                        state <= LOAD_WEIGHTS;
                        current_layer <= 0;
                        weight_addr <= 0;
                        chunk_start_addr <= 0;
                        chunk_counter <= 0;
                        load_weights <= 1;
                        process_done <= 0;
                        weight_load_counter <= 0;
                        input_has_color <= (neighborhood != {9{24'h000000}}) && (neighborhood != {9{24'hFFFFFF}});
                    end
                end

                LOAD_WEIGHTS: begin
                weight_addr <= weight_addr + 1;
                weight_load_counter <= weight_load_counter + 1;
                if (weight_load_counter == 180) begin // Adjust based on total weights
                state <= PROCESS_LAYERS;
                load_weights <= 0;
                current_layer <= 0;
                start_layer[0] <= 1; // Start the first layer (upsample)
                end
                end

                PROCESS_LAYERS: begin
                    layer_wait_counter <= layer_wait_counter + 1;
                    
                    if (layer_done[current_layer]) begin
                        start_layer[current_layer] <= 0;
                        if (current_layer == CONV_LAYERS) begin
                            pixel_out <= relu_output;
                            pixel_done <= 1;
                            pixel_processed_counter <= pixel_processed_counter + 1;
                            output_has_color <= (relu_output != 24'h000000) && (relu_output != 24'hFFFFFF);
                            
                            if (pixel_processed_counter >= WIDTH * HEIGHT - 1) begin
                                state <= FINISH;
                            end else begin
                                current_layer <= 0;
                                start_layer[0] <= 1; // Start processing next pixel
                            end
                        end else begin
                            current_layer <= current_layer + 1;
                            start_layer[current_layer + 1] <= 1;
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
                    pixel_done <= 1;
                    state <= IDLE;
                end
            endcase

            // debug_leds <= upsample_leds;

            // Debug LED indicators
            // debug_leds[0] <= output_has_color;  // Output color check
            // debug_leds[1] <= (state == LOAD_WEIGHTS);
            // debug_leds[2] <= (state == PROCESS_LAYERS);
            // debug_leds[3] <= (state == FINISH);
            // debug_leds[4] <= process_done;
            // debug_leds[5] <= layer_timeout;
            // debug_leds[6] <= (pixel_processed_counter > 0);
            // debug_leds[7] <= input_has_color;  // Input color check
        end
    end
endmodule



