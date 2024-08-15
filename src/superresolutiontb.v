`timescale 10ns / 1ns

module superresolution_tb;

    // Parameters
    parameter PIXEL_WIDTH = 24;
    parameter WEIGHT_ADDR_WIDTH = 18;
    parameter WIDTH = 320;
    parameter HEIGHT = 240;

    // Inputs
    reg clk;
    reg rst_n;
    reg [8:0] bram_addr;
    reg start_process;
    reg [9:0] x_in;
    reg [9:0] y_in;
    reg [9*PIXEL_WIDTH-1:0] neighborhood;

    // Outputs
    wire [PIXEL_WIDTH-1:0] pixel_out;
    wire process_done;
    wire pixel_done;
    // wire [7:0] debug_leds;

    // Instantiate the Unit Under Test (UUT)
    superresolution #(
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH),
        .WIDTH(WIDTH),
        .HEIGHT(HEIGHT)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .bram_addr(bram_addr),
        .start_process(start_process),
        .x_in(x_in),
        .y_in(y_in),
        .neighborhood(neighborhood),
        .pixel_out(pixel_out),
        .process_done(process_done),
        .pixel_done(pixel_done)//,
        // .debug_leds(debug_leds)
    );

    // Clock generation (100MHz)
    always begin
        #5 clk = ~clk;
    end

    // Test procedure
    initial begin
        // Initialize inputs
        clk = 0;
        rst_n = 0;
        bram_addr = 0;
        start_process = 0;
        x_in = 0;
        y_in = 0;
        neighborhood = 0;

        // Reset
        #100;
        rst_n = 1;

        // Infinite loop to run different scenarios
        forever begin
            // Scenario 1
            start_process = 1;
            x_in = 10;
            y_in = 10;
            neighborhood = {
                24'h010203, 24'h040506, 24'h070809,
                24'h0A0B0C, 24'h0D0E0F, 24'h101112,
                24'h131415, 24'h161718, 24'h191A1B
            };

            // Wait for processing to complete
            wait(pixel_done);
            #10;

            // Display results
            $display("Scenario 1 - Pixel out: %h", pixel_out);

            // Scenario 2
            #100;
            start_process = 1;
            x_in = 20;
            y_in = 20;
            neighborhood = {
                24'h1F1E1D, 24'h1C1B1A, 24'h191817,
                24'h161514, 24'h131211, 24'h100F0E,
                24'h0D0C0B, 24'h0A0908, 24'h070605
            };

            // Wait for processing to complete
            wait(pixel_done);
            #10;

            // Display results
            $display("Scenario 2 - Pixel out: %h", pixel_out);

            // Scenario 3
            #100;
            start_process = 1;
            x_in = 30;
            y_in = 30;
            neighborhood = {
                24'h001122, 24'h334455, 24'h667788,
                24'h99AABB, 24'hCCDDEE, 24'hFF0011,
                24'h223344, 24'h556677, 24'h8899AA
            };

            // Wait for processing to complete
            wait(pixel_done);
            #10;

            // Display results
            $display("Scenario 3 - Pixel out: %h", pixel_out);

            // Delay before restarting scenarios
            #100;
        end

    end

    // Monitor process_done and pixel_done signals
    always @(posedge process_done) begin
        $display("Process done at time %t", $time);
    end

    always @(posedge pixel_done) begin
        $display("Pixel done at time %t", $time);
    end

    // Waveform dumping
    initial begin
        $dumpfile("waveform.vcd");  // Specifies the name of the waveform file
        $dumpvars(0, superresolution_tb);  // Dumps all variables in your top module

        // End simulation after 10,000 ns
        #2000000;
        $finish;
    end

endmodule
