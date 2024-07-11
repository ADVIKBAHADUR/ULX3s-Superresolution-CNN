module Conv2D (
    input wire clk,
    input wire rst_n,
    input wire [215:0] input_data,
    output reg [431:0] output_data
);
    wire signed [31:0] weight_data;
    wire signed [31:0] bias_data;
    reg [15:0] weight_addr;
    reg [15:0] bias_addr;
    
    // Instantiate the ROM module for weights
    rom #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(16),
        .INIT_FILE("weights.mif")
    ) rom_weights (
        .addr(weight_addr),
        .q(weight_data),
        .clk(clk)
    );

    // Instantiate the ROM module for biases
    rom #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(16),
        .INIT_FILE("biases.mif")
    ) rom_biases (
        .addr(bias_addr),
        .q(bias_data),
        .clk(clk)
    );

    reg [3:0] state;
    reg [5:0] kernel;
    reg [2:0] conv;
    reg [2:0] depth;
    reg [2:0] i;
    reg [2:0] j;
    reg [1:0] ki;
    reg [1:0] kj;
    reg signed [47:0] sum;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= 0;
            conv <= 0;
            kernel <= 0;
            depth <= 0;
            i <= 0;
            j <= 0;
            ki <= 0;
            kj <= 0;
            sum <= 0;
            output_data <= 0;
        end else begin
            case (state)
                0: begin
                    sum <= 0;
                    state <= 1;
                end
                1: begin
                    weight_addr <= (conv * 64 * 64 * 3 * 3) + (kernel * 64 * 3 * 3) + (depth * 3 * 3) + (ki * 3) + kj;
                    state <= 2;
                end
                2: begin
                    sum <= sum + (input_data[((2 - i) * 3 + (2 - j)) * 3 + (2 - depth)] * weight_data);
                    if (kj == 2) begin
                        kj <= 0;
                        if (ki == 2) begin
                            ki <= 0;
                            if (depth == 2) begin
                                depth <= 0;
                                state <= 3;
                            end else begin
                                depth <= depth + 1;
                                state <= 1;
                            end
                        end else begin
                            ki <= ki + 1;
                            state <= 1;
                        end
                    end else begin
                        kj <= kj + 1;
                        state <= 1;
                    end
                end
                3: begin
                    bias_addr <= conv * 64 + kernel;
                    state <= 4;
                end
                4: begin
                    sum <= sum + bias_data;
                    output_data[((2 - i) * 3 + (2 - j)) * 3 + (2 - kernel)] <= sum[15:0];
                    state <= 5;
                end
                5: begin
                    if (kernel == 63) begin
                        kernel <= 0;
                        if (j == 2) begin
                            j <= 0;
                            if (i == 2) begin
                                i <= 0;
                                if (conv == 4) begin
                                    conv <= 0;
                                    state <= 0;  // Convolution complete
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
            endcase
        end
    end
endmodule

