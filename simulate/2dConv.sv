module Conv2D(
    input wire clk,          // Clock
    input wire rst_n,        // Reset (active low)
    input wire [7:0] input_data [0:2][0:2][0:2],
    output reg [15:0] output_data [0:2][0:2][0:2]
);

    reg signed [31:0] Weights [0:4][0:63][0:63][0:2][0:2]; // [ConvLayer][Kernel][Depth][Height][Width]
    reg signed [31:0] Biases [0:4][0:63]; // [ConvLayer][Kernel]

    // Assuming modelReader module reads the weights and biases into the registers
    modelReader SuperResolution (.clk(clk), .rst_n(rst_n), .conv_weights(Weights), .conv_biases(Biases));

    reg [3:0] state; // State register
    reg [5:0] kernel;
    reg [2:0] conv, depth, i, j;
    reg [1:0] ki, kj;
    reg signed [47:0] sum; // Accumulator for sum (large enough to avoid overflow)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset logic
            state <= 0;
            conv <= 0;
            kernel <= 0;
            depth <= 0;
            i <= 0;
            j <= 0;
            ki <= 0;
            kj <= 0;
            sum <= 0;
            // Clear output_data
            output_data[0][0][0] <= 0;
            output_data[0][0][1] <= 0;
            output_data[0][0][2] <= 0;
            output_data[0][1][0] <= 0;
            output_data[0][1][1] <= 0;
            output_data[0][1][2] <= 0;
            output_data[0][2][0] <= 0;
            output_data[0][2][1] <= 0;
            output_data[0][2][2] <= 0;
            output_data[1][0][0] <= 0;
            output_data[1][0][1] <= 0;
            output_data[1][0][2] <= 0;
            output_data[1][1][0] <= 0;
            output_data[1][1][1] <= 0;
            output_data[1][1][2] <= 0;
            output_data[1][2][0] <= 0;
            output_data[1][2][1] <= 0;
            output_data[1][2][2] <= 0;
            output_data[2][0][0] <= 0;
            output_data[2][0][1] <= 0;
            output_data[2][0][2] <= 0;
            output_data[2][1][0] <= 0;
            output_data[2][1][1] <= 0;
            output_data[2][1][2] <= 0;
            output_data[2][2][0] <= 0;
            output_data[2][2][1] <= 0;
            output_data[2][2][2] <= 0;
        end else begin
            case (state)
                0: begin
                    // Initialize sum for new convolution
                    sum <= 0;
                    state <= 1;
                end
                1: begin
                    // Perform convolution operation
                    sum <= sum + input_data[i][j][depth] * Weights[conv][kernel][depth][ki][kj];
                    if (kj == 2) begin
                        kj <= 0;
                        if (ki == 2) begin
                            ki <= 0;
                            if (depth == 2) begin
                                depth <= 0;
                                state <= 2;
                            end else begin
                                depth <= depth + 1;
                            end
                        end else begin
                            ki <= ki + 1;
                        end
                    end else begin
                        kj <= kj + 1;
                    end
                end
                2: begin
                    // Add bias and store result
                    sum <= sum + Biases[conv][kernel];
                    output_data[i][j][kernel] <= sum[15:0];
                    state <= 3;
                end
                3: begin
                    // Update indices
                    if (kernel == 63) begin
                        kernel <= 0;
                        if (j == 2) begin
                            j <= 0;
                            if (i == 2) begin
                                i <= 0;
                                if (conv == 4) begin
                                    conv <= 0;
                                    state <= 4; // All convolutions done
                                end else begin
                                    conv <= conv + 1;
                                    state <= 0;
                                end
                            end else begin
                                i <= i + 1;
                                state <= 0;
                            end
                        end else begin
                            j <= j + 1;
                            state <= 0;
                        end
                    end else begin
                        kernel <= kernel + 1;
                        state <= 0;
                    end
                end
                4: begin
                    // Idle state or other operations
                    // Additional states can be added as needed
                end
            endcase
        end
    end
endmodule
