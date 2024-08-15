module conv_layer #(
    parameter IN_CHANNELS = 12,
    parameter OUT_CHANNELS = 12,
    parameter KERNEL_SIZE = 3,
    parameter DATA_WIDTH = 16,
    parameter WEIGHT_ADDR_WIDTH = 20
)(
    input wire clk,
    input wire rst_n,
    input wire [DATA_WIDTH-1:0] weight_in,
    input wire load_weights,
    input wire [WEIGHT_ADDR_WIDTH-1:0] weight_addr,
    input wire start_conv,
    input wire [IN_CHANNELS * DATA_WIDTH-1:0] pixel_in,
    output reg [OUT_CHANNELS * DATA_WIDTH-1:0] pixel_out,
    output reg conv_done,
    output reg [7:0] debug_leds
);
    localparam WEIGHT_MEM_DEPTH = IN_CHANNELS * OUT_CHANNELS * KERNEL_SIZE * KERNEL_SIZE;
    localparam BIAS_MEM_DEPTH = OUT_CHANNELS;
    localparam TOTAL_MEM_DEPTH = WEIGHT_MEM_DEPTH + BIAS_MEM_DEPTH;
    
    // Intermediate results
    reg signed [2*DATA_WIDTH+1:0] accum [0:OUT_CHANNELS-1];
    
    // Convolution state machine
    reg [2:0] conv_state;
    reg [7:0] i, j, k;
    localparam IDLE = 3'd0, CONV = 3'd1, FINISH = 3'd2;

    // Debug signals
    reg weights_nonzero;
    reg input_nonzero;
    reg accum_nonzero;
    reg bias_nonzero;
    reg pre_output_nonzero;
    reg output_nonzero;
    reg [OUT_CHANNELS-1:0] channel_nonzero;
    reg weight_toggle;
    reg [15:0] nonzero_weight_count;
    reg [31:0] cycle_counter;

    // Temporary variables for convolution
    reg signed [DATA_WIDTH-1:0] weight_val;
    reg signed [DATA_WIDTH-1:0] input_val;
    reg signed [2*DATA_WIDTH-1:0] mult_result;
    reg signed [2*DATA_WIDTH+1:0] accum_with_bias;

    // Weight storage
    reg [DATA_WIDTH-1:0] weight_mem [0:TOTAL_MEM_DEPTH-1];
    reg [WEIGHT_ADDR_WIDTH-1:0] weight_read_addr;

    integer reset_index;

    // Weight reading logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weights_nonzero <= 0;
            weight_read_addr <= 0;
            weight_toggle <= 0;
            nonzero_weight_count <= 0;
            for (reset_index = 0; reset_index < TOTAL_MEM_DEPTH; reset_index = reset_index + 1) begin
                weight_mem[reset_index] <= 0;
            end
        end else if (load_weights) begin
            weight_mem[weight_addr] <= weight_in;
            if (weight_in != 0) begin
                weights_nonzero <= 1;
                weight_toggle <= ~weight_toggle;
                nonzero_weight_count <= nonzero_weight_count + 1;
            end
        end else if (conv_state == CONV) begin
            weight_read_addr <= i * IN_CHANNELS * KERNEL_SIZE * KERNEL_SIZE +
                                j * KERNEL_SIZE * KERNEL_SIZE +
                                k;
        end
    end

    // Main convolution logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            conv_state <= IDLE;
            i <= 0;
            j <= 0;
            k <= 0;
            conv_done <= 0;
            input_nonzero <= 0;
            accum_nonzero <= 0;
            bias_nonzero <= 0;
            pre_output_nonzero <= 0;
            output_nonzero <= 0;
            channel_nonzero <= 0;
            cycle_counter <= 0;
            for (reset_index = 0; reset_index < OUT_CHANNELS; reset_index = reset_index + 1) begin
                accum[reset_index] <= 0;
                pixel_out[reset_index*DATA_WIDTH +: DATA_WIDTH] <= 0;
            end
        end else begin
            case (conv_state)
                IDLE: begin
                    if (start_conv) begin
                        conv_state <= CONV;
                        i <= 0;
                        j <= 0;
                        k <= 0;
                        input_nonzero <= 0;
                        accum_nonzero <= 0;
                        pre_output_nonzero <= 0;
                        output_nonzero <= 0;
                        channel_nonzero <= 0;
                        cycle_counter <= 0;
                        for (reset_index = 0; reset_index < OUT_CHANNELS; reset_index = reset_index + 1) begin
                            accum[reset_index] <= 0;
                        end

                        // Check input
                        for (reset_index = 0; reset_index < IN_CHANNELS; reset_index = reset_index + 1) begin
                            if (pixel_in[reset_index*DATA_WIDTH +: DATA_WIDTH] != 0) begin
                                input_nonzero <= 1;
                            end
                        end
                    end
                end

                CONV: begin
                    // Perform convolution
                    weight_val = $signed(weight_mem[weight_read_addr]);
                    input_val = $signed(pixel_in[j*DATA_WIDTH +: DATA_WIDTH]);
                    mult_result = weight_val * input_val;
                    accum[i] <= accum[i] + mult_result;
                    cycle_counter <= cycle_counter + 1;

                    if (mult_result != 0) begin
                        accum_nonzero <= 1;
                    end

                    // Update counters
                    if (k < KERNEL_SIZE * KERNEL_SIZE - 1) begin
                        k <= k + 1;
                    end else begin
                        k <= 0;
                        if (j < IN_CHANNELS - 1) begin
                            j <= j + 1;
                        end else begin
                            j <= 0;
                            if (i < OUT_CHANNELS - 1) begin
                                i <= i + 1;
                            end else begin
                                conv_state <= FINISH;
                            end
                        end
                    end
                end

                FINISH: begin
                    for (reset_index = 0; reset_index < OUT_CHANNELS; reset_index = reset_index + 1) begin
                        // Apply bias
                        weight_read_addr <= WEIGHT_MEM_DEPTH + reset_index;
                        accum_with_bias = accum[reset_index] + {{(DATA_WIDTH+2){weight_mem[weight_read_addr][DATA_WIDTH-1]}}, weight_mem[weight_read_addr]};
                        
                        if (accum_with_bias != 0) begin
                            channel_nonzero[reset_index] <= 1;
                        end

                        if (weight_mem[weight_read_addr] != 0) bias_nonzero <= 1;

                        // Apply activation and store result
                        if (accum_with_bias > {{(DATA_WIDTH){1'b0}}, {DATA_WIDTH{1'b1}}}) begin
                            pixel_out[reset_index*DATA_WIDTH +: DATA_WIDTH] <= {DATA_WIDTH{1'b1}}; // Saturate to max positive
                            pre_output_nonzero <= 1;
                        end else if (accum_with_bias < {{(DATA_WIDTH){1'b1}}, {DATA_WIDTH{1'b0}}}) begin
                            pixel_out[reset_index*DATA_WIDTH +: DATA_WIDTH] <= {1'b1, {(DATA_WIDTH-1){1'b0}}}; // Saturate to max negative
                            pre_output_nonzero <= 1;
                        end else begin
                            pixel_out[reset_index*DATA_WIDTH +: DATA_WIDTH] <= accum_with_bias[DATA_WIDTH-1:0]; // Normal case
                            if (accum_with_bias[DATA_WIDTH-1:0] != 0) begin
                                pre_output_nonzero <= 1;
                            end
                        end

                        if (pixel_out[reset_index*DATA_WIDTH +: DATA_WIDTH] != 0) begin
                            output_nonzero <= 1;
                        end
                    end

                    conv_done <= 1;
                    conv_state <= IDLE;
                end
            endcase
        end
    end

    // Debug LED logic
    always @(posedge clk) begin
        debug_leds[0] <= weights_nonzero;
        debug_leds[1] <= input_nonzero;
        debug_leds[2] <= accum_nonzero;
        debug_leds[3] <= bias_nonzero;
        debug_leds[4] <= pre_output_nonzero;
        debug_leds[5] <= output_nonzero;
        debug_leds[6] <= weight_toggle;
        debug_leds[7] <= (conv_state == CONV);
    end
endmodule