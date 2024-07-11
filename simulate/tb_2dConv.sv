`timescale 1ns/1ps

module tb_Conv2D;
    // Parameters
    localparam CLK_PERIOD = 10;

    // Inputs
    reg clk;
    reg rst_n;
    reg [7:0] input_data [0:2][0:2][0:2];

    // Outputs
    wire [15:0] output_data [0:2][0:2][0:2];

    // Instantiate the DUT (Device Under Test)
    Conv2D dut (
        .clk(clk),
        .rst_n(rst_n),
        .input_data(input_data),
        .output_data(output_data)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Test stimulus
    initial begin
        // Initialize inputs
        rst_n = 0;
        input_data[0][0][0] = 8'h01; input_data[0][0][1] = 8'h02; input_data[0][0][2] = 8'h03;
        input_data[0][1][0] = 8'h04; input_data[0][1][1] = 8'h05; input_data[0][1][2] = 8'h06;
        input_data[0][2][0] = 8'h07; input_data[0][2][1] = 8'h08; input_data[0][2][2] = 8'h09;
        input_data[1][0][0] = 8'h0A; input_data[1][0][1] = 8'h0B; input_data[1][0][2] = 8'h0C;
        input_data[1][1][0] = 8'h0D; input_data[1][1][1] = 8'h0E; input_data[1][1][2] = 8'h0F;
        input_data[1][2][0] = 8'h10; input_data[1][2][1] = 8'h11; input_data[1][2][2] = 8'h12;
        input_data[2][0][0] = 8'h13; input_data[2][0][1] = 8'h14; input_data[2][0][2] = 8'h15;
        input_data[2][1][0] = 8'h16; input_data[2][1][1] = 8'h17; input_data[2][1][2] = 8'h18;
        input_data[2][2][0] = 8'h19; input_data[2][2][1] = 8'h1A; input_data[2][2][2] = 8'h1B;

        // Release reset
        #20;
        rst_n = 1;

        // Wait for some time to let the DUT process the inputs
        #1000;

        // Check results (you can add assertions here)
        $display("Simulation completed");

        // End simulation
        $finish;
    end
endmodule

