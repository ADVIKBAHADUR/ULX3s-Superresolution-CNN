`timescale 1ns / 1ps

module top_module_tb();

    // Inputs
    reg clk;
    reg rst_n;
    reg [3:0] key;
    reg cmos_pclk;
    reg cmos_href;
    reg cmos_vsync;
    reg [7:0] cmos_db;
    
    // Inouts
    wire cmos_sda;
    wire cmos_scl;
    
    // Outputs
    wire [7:0] led;
    wire sdram_clk;
    wire sdram_cke;
    wire sdram_cs_n;
    wire sdram_ras_n;
    wire sdram_cas_n;
    wire sdram_we_n;
    wire [12:0] sdram_addr;
    wire [1:0] sdram_ba;
    wire [1:0] sdram_dqm;
    wire [3:0] gpdi_dp;
    wire cmos_rst_n;
    wire cmos_pwdn;
    wire cmos_xclk;
    
    // Bidirectional
    wire [15:0] sdram_dq;

    // Instantiate the Unit Under Test (UUT)
    top_module uut (
        .clk(clk),
        .rst_n(rst_n),
        .key(key),
        .cmos_pclk(cmos_pclk),
        .cmos_href(cmos_href),
        .cmos_vsync(cmos_vsync),
        .cmos_db(cmos_db),
        .cmos_sda(cmos_sda),
        .cmos_scl(cmos_scl),
        .led(led),
        .sdram_clk(sdram_clk),
        .sdram_cke(sdram_cke),
        .sdram_cs_n(sdram_cs_n),
        .sdram_ras_n(sdram_ras_n),
        .sdram_cas_n(sdram_cas_n),
        .sdram_we_n(sdram_we_n),
        .sdram_addr(sdram_addr),
        .sdram_ba(sdram_ba),
        .sdram_dqm(sdram_dqm),
        .sdram_dq(sdram_dq),
        .gpdi_dp(gpdi_dp),
        .cmos_rst_n(cmos_rst_n),
        .cmos_pwdn(cmos_pwdn),
        .cmos_xclk(cmos_xclk)
    );

    // Clock generation for 25MHz
    initial begin
        clk = 0;
        forever #20 clk = ~clk; // 25MHz clock (period = 40ns)
    end

    // Test stimulus
    initial begin
        // Initialize inputs
        rst_n = 0;
        key = 4'b0000;
        cmos_pclk = 0;
        cmos_href = 0;
        cmos_vsync = 0;
        cmos_db = 8'h00;

        // Release reset after 10 clock cycles
        repeat(10) @(posedge clk);
        rst_n = 1;

        // Test case 1: Normal operation
        repeat(100) @(posedge clk);
        key = 4'b0001; // Set some key value
        
        // Simulate camera input (adjust timing if necessary)
        repeat (1000) begin
            #40 cmos_pclk = ~cmos_pclk; // Assuming camera clock is also 25MHz
            if (cmos_pclk) begin
                cmos_href = 1;
                cmos_db = $random; // Generate random pixel data
            end
        end

        // Test case 2: Change display mode
        repeat(100) @(posedge clk);
        key = 4'b0100; // Switch display mode

        // Continue simulation...
        repeat(1000) @(posedge clk);

        // Add more test cases as needed

        $finish;
    end

    // Monitor
    initial begin
        $monitor("Time=%0t: led=%b, gpdi_dp=%b", $time, led, gpdi_dp);
    end

endmodule   