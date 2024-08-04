module weight_loader(
    input clk,
    input reset,
    output reg [ADDR_WIDTH-1:0] rom_addr,
    input [DATA_WIDTH*BATCH_SIZE-1:0] rom_data,
    output reg [DATA_WIDTH-1:0] weights[0:NUM_WEIGHTS-1][0:8][0:IN_CHANNELS-1][0:OUT_CHANNELS-1],
    output reg [DATA_WIDTH-1:0] biases[0:NUM_BIASES-1][0:OUT_CHANNELS-1]
);
    parameter DATA_WIDTH = 8;
    parameter ADDR_WIDTH = 16;
    parameter BATCH_SIZE = 8;
    parameter NUM_WEIGHTS = 5;  // Number of convolution layers
    parameter NUM_BIASES = 5;   // Number of convolution layers
    parameter IN_CHANNELS = 9;
    parameter OUT_CHANNELS = 9;

    reg [ADDR_WIDTH-1:0] load_counter;
    reg [3:0] state;

    // Define the total size of each layer
    localparam UPSAMPLE_WEIGHT_SIZE = 3 * 12 * 9;
    localparam UPSAMPLE_BIAS_SIZE = 12;
    localparam CONV1_WEIGHT_SIZE = 3 * 9 * 9;
    localparam CONV1_BIAS_SIZE = 9;
    localparam CONV2_WEIGHT_SIZE = 9 * 9 * 9;
    localparam CONV2_BIAS_SIZE = 9;
    localparam CONV3_WEIGHT_SIZE = 9 * 9 * 9;
    localparam CONV3_BIAS_SIZE = 9;
    localparam CONV4_WEIGHT_SIZE = 9 * 9 * 9;
    localparam CONV4_BIAS_SIZE = 9;
    localparam CONV5_WEIGHT_SIZE = 9 * 3 * 9;
    localparam CONV5_BIAS_SIZE = 3;

    // Calculate the starting addresses of each convolution layer's weights and biases
    localparam UPSAMPLE_WEIGHT_START = 0;
    localparam UPSAMPLE_BIAS_START = UPSAMPLE_WEIGHT_START + UPSAMPLE_WEIGHT_SIZE;
    localparam CONV1_WEIGHT_START = UPSAMPLE_BIAS_START + UPSAMPLE_BIAS_SIZE;
    localparam CONV1_BIAS_START = CONV1_WEIGHT_START + CONV1_WEIGHT_SIZE;
    localparam CONV2_WEIGHT_START = CONV1_BIAS_START + CONV1_BIAS_SIZE;
    localparam CONV2_BIAS_START = CONV2_WEIGHT_START + CONV2_WEIGHT_SIZE;
    localparam CONV3_WEIGHT_START = CONV2_BIAS_START + CONV2_BIAS_SIZE;
    localparam CONV3_BIAS_START = CONV3_WEIGHT_START + CONV3_WEIGHT_SIZE;
    localparam CONV4_WEIGHT_START = CONV3_BIAS_START + CONV3_BIAS_SIZE;
    localparam CONV4_BIAS_START = CONV4_WEIGHT_START + CONV4_WEIGHT_SIZE;
    localparam CONV5_WEIGHT_START = CONV4_BIAS_START + CONV4_BIAS_SIZE;

    // State machine states
    localparam STATE_IDLE = 0;
    localparam STATE_LOAD_WEIGHTS = 1;
    localparam STATE_LOAD_BIASES = 2;
    localparam STATE_DONE = 3;

    reg [4:0] layer_index;
    reg [7:0] channel_index;
    reg [7:0] weight_index;
    reg [7:0] bias_index;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            load_counter <= 0;
            rom_addr <= UPSAMPLE_WEIGHT_START;
            state <= STATE_IDLE;
            layer_index <= 0;
            channel_index <= 0;
            weight_index <= 0;
            bias_index <= 0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    // Initialize loading process
                    if (layer_index < NUM_WEIGHTS) begin
                        state <= STATE_LOAD_WEIGHTS;
                        rom_addr <= UPSAMPLE_WEIGHT_START;
                    end else begin
                        state <= STATE_DONE;
                    end
                end

                STATE_LOAD_WEIGHTS: begin
                    // Load weights for each layer
                    if (load_counter < UPSAMPLE_WEIGHT_SIZE) begin
                        weights[layer_index][weight_index][channel_index][bias_index] <= rom_data[DATA_WIDTH-1:0];
                        load_counter <= load_counter + 1;
                        rom_addr <= rom_addr + 1;

                        // Increment indices to go through all weights
                        if (weight_index == 8 && channel_index == 8) begin
                            layer_index <= layer_index + 1;
                            state <= STATE_LOAD_BIASES;
                        end else if (channel_index == 8) begin
                            channel_index <= 0;
                            weight_index <= weight_index + 1;
                        end else begin
                            channel_index <= channel_index + 1;
                        end
                    end else begin
                        state <= STATE_LOAD_BIASES;
                    end
                end

                STATE_LOAD_BIASES: begin
                    // Load biases for each layer
                    if (load_counter < UPSAMPLE_BIAS_SIZE) begin
                        biases[layer_index][bias_index] <= rom_data[DATA_WIDTH-1:0];
                        load_counter <= load_counter + 1;
                        rom_addr <= rom_addr + 1;

                        // Increment bias index
                        if (bias_index == OUT_CHANNELS - 1) begin
                            layer_index <= layer_index + 1;
                            if (layer_index < NUM_WEIGHTS) begin
                                state <= STATE_LOAD_WEIGHTS;
                            end else begin
                                state <= STATE_DONE;
                            end
                        end else begin
                            bias_index <= bias_index + 1;
                        end
                    end else begin
                        state <= STATE_DONE;
                    end
                end

                STATE_DONE: begin
                    // Do nothing, loading is complete
                end
            endcase
        end
    end
endmodule

