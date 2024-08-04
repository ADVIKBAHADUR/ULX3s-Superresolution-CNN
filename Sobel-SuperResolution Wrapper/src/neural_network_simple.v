module neural_network_simple(
    input wire clk,
    input wire reset,
    input wire [44:0] r_channel,
    input wire [53:0] g_channel,
    input wire [44:0] b_channel,
    output reg [7:0] output_r,
    output reg [7:0] output_g,
    output reg [7:0] output_b
);
    reg [7:0] sum_r, sum_g, sum_b;
    integer i;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            sum_r <= 8'd0;
            sum_g <= 8'd0;
            sum_b <= 8'd0;
            output_r <= 8'd0;
            output_g <= 8'd0;
            output_b <= 8'd0;
        end else begin
            sum_r <= 8'd0;
            sum_g <= 8'd0;
            sum_b <= 8'd0;
            for (i = 0; i < 9; i = i + 1) begin
                sum_r <= sum_r + r_channel[i*5 +: 5];
                sum_g <= sum_g + g_channel[i*6 +: 6];
                sum_b <= sum_b + b_channel[i*5 +: 5];
            end
            output_r <= sum_r;
            output_g <= sum_g;
            output_b <= sum_b;
        end
    end
endmodule
