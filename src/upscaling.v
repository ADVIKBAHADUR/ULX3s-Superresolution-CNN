module upsample_layer #(
    parameter IN_CHANNELS = 3,
    parameter OUT_CHANNELS = 12,
    parameter KERNEL_SIZE = 3,
    parameter DATA_WIDTH = 16,
    parameter WEIGHT_ADDR_WIDTH = 20
)(
    input wire clk,
    input wire rst_n,
    input wire [IN_CHANNELS*DATA_WIDTH-1:0] pixel_in,
    input wire [DATA_WIDTH-1:0] weight_in,
    input wire load_weights,
    input wire [WEIGHT_ADDR_WIDTH-1:0] weight_addr,
    input wire start_conv,
    output reg [OUT_CHANNELS*DATA_WIDTH-1:0] pixel_out,
    output reg conv_done,
    output reg [7:0] debug_leds
);
    // Local parameters
    localparam TOTAL_WEIGHTS = IN_CHANNELS * OUT_CHANNELS * KERNEL_SIZE * KERNEL_SIZE;
    
    // Internal signals
    reg signed [DATA_WIDTH-1:0] weights [0:TOTAL_WEIGHTS-1];
    reg signed [DATA_WIDTH-1:0] biases [0:OUT_CHANNELS-1];
    reg signed [2*DATA_WIDTH+1:0] accum [0:OUT_CHANNELS-1];
    
    // Debug signals
    reg weights_nonzero;
    reg input_nonzero;
    reg accum_nonzero;
    reg bias_nonzero;
    reg pre_output_nonzero;
    reg output_nonzero;
    reg [OUT_CHANNELS-1:0] channel_nonzero;
    reg [31:0] cycle_counter;
    reg [7:0] outerloopcounter;
    
    // Convolution state machine
    reg [2:0] conv_state;
    reg [7:0] i, j, k;
    localparam IDLE = 0, CONV = 1, FINISH = 2;
    
    // Temporary variables for convolution
    reg signed [DATA_WIDTH-1:0] weight_val;
    reg signed [DATA_WIDTH-1:0] input_val;
    reg signed [2*DATA_WIDTH-1:0] mult_result;
    reg signed [2*DATA_WIDTH+1:0] accum_with_bias;
    
    integer reset_index;

    // Sequential logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            conv_done <= 0;
            for (reset_index = 0; reset_index < OUT_CHANNELS; reset_index = reset_index + 1) begin
                pixel_out[reset_index*DATA_WIDTH +: DATA_WIDTH] <= 0;
                accum[reset_index] <= 0;
            end
            for (reset_index = 0; reset_index < TOTAL_WEIGHTS; reset_index = reset_index + 1) begin
                weights[reset_index] <= 0;
            end
            for (reset_index = 0; reset_index < OUT_CHANNELS; reset_index = reset_index + 1) begin
                biases[reset_index] <= 0;
            end
            debug_leds <= 8'b0;
            outerloopcounter <= 0;
            cycle_counter <= 0;
            weights_nonzero <= 0;
            input_nonzero <= 0;
            accum_nonzero <= 0;
            bias_nonzero <= 0;
            pre_output_nonzero <= 0;
            output_nonzero <= 0;
            channel_nonzero <= 0;
            conv_state <= IDLE;
            i <= 0;
            j <= 0;
            k <= 0;
        end else begin
            if (load_weights) begin
                if (weight_addr < TOTAL_WEIGHTS) begin
                    weights[weight_addr] <= $signed(weight_in);
                    if (weight_in != 0) begin
                        weights_nonzero <= 1;
                    end
                end else if (weight_addr < TOTAL_WEIGHTS + OUT_CHANNELS) begin
                    biases[weight_addr - TOTAL_WEIGHTS] <= $signed(weight_in);
                    if (weight_in != 0) begin
                        bias_nonzero <= 1;
                    end
                end
            end else begin
                case (conv_state)
                    IDLE: begin
                        if (start_conv) begin
                            conv_state <= CONV;
                            i <= 0;
                            j <= 0;
                            k <= 0;
                            outerloopcounter <= 0;
                            conv_done <= 0;
                            input_nonzero <= 0;
                            accum_nonzero <= 0;
                            pre_output_nonzero <= 0;
                            output_nonzero <= 0;
                            channel_nonzero <= 0;
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
                        weight_val = weights[(i*IN_CHANNELS + j)*KERNEL_SIZE*KERNEL_SIZE + k];
                        input_val = $signed(pixel_in[((j*KERNEL_SIZE*KERNEL_SIZE + k)*DATA_WIDTH) % ($bits(pixel_in)) +: DATA_WIDTH]);
                        mult_result = weight_val * input_val;
                        accum[i] <= accum[i] + mult_result;
                        cycle_counter <= cycle_counter + 1;
                        
                        if (k < KERNEL_SIZE*KERNEL_SIZE - 1) begin
                            k <= k + 1;
                        end else begin
                            k <= 0;
                            if (j < IN_CHANNELS - 1) begin
                                j <= j + 1;
                            end else begin
                                j <= 0;
                                accum_with_bias = accum[i] + {{(DATA_WIDTH+2){biases[i][DATA_WIDTH-1]}}, biases[i]};
                                accum[i] <= accum_with_bias;
                                if (accum_with_bias != 0) begin
                                    accum_nonzero <= 1;
                                    channel_nonzero[i] <= 1;
                                end
                                if (i < OUT_CHANNELS - 1) begin
                                    i <= i + 1;
                                    outerloopcounter <= outerloopcounter + 1;
                                end else begin
                                    conv_state <= FINISH;
                                end
                            end
                        end
                    end
                    
                    FINISH: begin
                        for (reset_index = 0; reset_index < OUT_CHANNELS; reset_index = reset_index + 1) begin
                            if (accum[reset_index] > {{(DATA_WIDTH){1'b0}}, {DATA_WIDTH{1'b1}}}) begin
                                pixel_out[reset_index*DATA_WIDTH +: DATA_WIDTH] <= {DATA_WIDTH{1'b1}}; // Saturate to max positive
                                pre_output_nonzero <= 1;
                            end else if (accum[reset_index] < {{(DATA_WIDTH){1'b1}}, {DATA_WIDTH{1'b0}}}) begin
                                pixel_out[reset_index*DATA_WIDTH +: DATA_WIDTH] <= {1'b1, {(DATA_WIDTH-1){1'b0}}}; // Saturate to max negative
                                pre_output_nonzero <= 1;
                            end else begin
                                pixel_out[reset_index*DATA_WIDTH +: DATA_WIDTH] <= accum[reset_index][DATA_WIDTH-1:0]; // Normal case
                                if (accum[reset_index][DATA_WIDTH-1:0] != 0) begin
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

            // Update debug LEDs
            debug_leds[0] <= weights_nonzero;
            debug_leds[1] <= input_nonzero;
            debug_leds[2] <= accum_nonzero;
            debug_leds[3] <= bias_nonzero;
            debug_leds[4] <= pre_output_nonzero;
            debug_leds[5] <= output_nonzero;
            debug_leds[6] <= |channel_nonzero;
            debug_leds[7] <= conv_done;
        end
    end
endmodule