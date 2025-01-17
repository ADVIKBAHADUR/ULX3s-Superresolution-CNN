module top_module(
    input wire clk,rst_n,
    input wire[3:0] key, //key[1:0] for threshold control, key[2] for switching display(RGB/Edge Detector), key[3] to automatically align sobel frame(if misaligned)
    //camera pinouts
    input wire cmos_pclk,cmos_href,cmos_vsync,
    input wire[7:0] cmos_db,
    inout cmos_sda,cmos_scl, 
    output wire cmos_rst_n, cmos_pwdn, cmos_xclk,
    //Debugging
    output[7:0] led, 
    //controller to sdram
    output wire sdram_clk,
    output wire sdram_cke, 
    output wire sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n, 
    output wire[12:0] sdram_addr,
    output wire[1:0] sdram_ba, 
    output wire[1:0] sdram_dqm, 
    inout[15:0] sdram_dq,
    //HDMI output
    output [3:0] gpdi_dp
);
 
    wire f2s_data_valid;
    reg [7:0] led_c, led_s; 
    reg [31:0] led_switch_counter;
    reg ledswitcher;
    wire[10:0] data_count_r,data_count_r_sobel;
    wire[16:0] dout,din;
    wire empty_fifo,empty;
    wire clk_vga,clk_sobel;
    wire state;
    wire rd_sobel;
    wire rd_en,rd_fifo;
    wire[16:0] sobel_data;
    wire[9:0] data_count_sobel;
    wire rd_en_sobel;
    wire[16:0] dout_sobel;
    reg[7:0] threshold=0;
    reg sobel=0;

    wire clk_sdram,clk_25_out;

    assign clk_25_out = clocks[0];
    assign clk_sdram = clocks[2];

    wire [3:0] clocks;
    ecp5pll
    #(
        .in_hz(25000000),
        .out0_hz(25000000),                 .out0_tol_hz(0),    // use this for 25MHz
        .out1_hz(50000000), .out1_deg( 90), .out1_tol_hz(0),
        .out2_hz(100000000), .out2_deg(180), .out2_tol_hz(0),  // SDRAM clock
        .out3_hz( 6000000), .out3_deg(300), .out3_tol_hz(0)
    )
    ecp5pll_inst
    (
        .clk_i(clk),
        .clk_o(clocks)
    );

    always @(posedge clk_25_out) begin
        if(!rst_n) begin
            threshold=0;
            sobel<=0;
            led_switch_counter <= 0;
            ledswitcher = 0;
        end
        else begin
            threshold=key1_tick? threshold+1:threshold;  //decrease sensitivity of sobel edge detection
            threshold=key2_tick? threshold-1:threshold;    //increase sensitivity of sobel edge detection
            sobel<=key3_tick? !sobel:sobel; //choose whether to display the raw video or the edge detected video

            led_switch_counter <= led_switch_counter + 1;
            if(led_switch_counter == 125000000) begin
                ledswitcher = !ledswitcher;
                led_switch_counter <=0;
            end

            if(ledswitcher) begin
                led = led_c;
            end else if (!ledswitcher) begin
                led = led_s;
            end
        end
    end
    
    // Module instantiations
    camera_interface m0 (
        .clk(clk_25_out),
        .clk_100(clk_sdram),
        .rst_n(rst_n),
        .key(),
        //sobel
        .rd_en_sobel(rd_en_sobel),
        .dout_sobel(dout_sobel),
        .data_count_r_sobel(data_count_r_sobel),
        //camera fifo IO
        .rd_en(rd_fifo),
        .data_count_r(data_count_r),
        .dout(dout),
        //camera pinouts
        .cmos_pclk(cmos_pclk),
        .cmos_href(cmos_href),
        .cmos_vsync(cmos_vsync),
        .cmos_db(cmos_db),
        .cmos_sda(cmos_sda),
        .cmos_scl(cmos_scl), 
        .cmos_rst_n(cmos_rst_n),
        .cmos_pwdn(cmos_pwdn),
        .cmos_xclk(cmos_xclk),
        //Debugging
        .led(led_c)
    );
     
    sdram_interface m1 (
        .clk(clk_sdram),
        .rst_n(rst_n),
        .clk_vga(clk_vga),
        .rd_en(rd_en),
        .sobel(sobel),
        //fifo for camera
        .data_count_camera_fifo(data_count_r),
        .din(dout),
        .rd_camera(rd_fifo),
        //sobel
        .sobel_data(sobel_data),
        .data_count_r(data_count_sobel),
        .rd_sobel(rd_sobel),
        //fifo for vga
        .empty_fifo(empty_fifo),
        .dout(din),
        //controller to sdram
        .sdram_clk(sdram_clk),
        .sdram_cke(sdram_cke), 
        .sdram_cs_n(sdram_cs_n),
        .sdram_ras_n(sdram_ras_n),
        .sdram_cas_n(sdram_cas_n),
        .sdram_we_n(sdram_we_n), 
        .sdram_addr(sdram_addr),
        .sdram_ba(sdram_ba), 
        .sdram_dqm(sdram_dqm),
        .sdram_dq(sdram_dq)
    );
     
    vga_interface m2 (
        .clk(clk_25_out),
        .rst_n(rst_n),
        .sobel(sobel),
        .align_tick(key[3]),
        //asyn_fifo IO
        .empty_fifo(empty_fifo),
        .din(din),
        .clk_vga(clk_vga),
        .rd_en(rd_en),
        .threshold(threshold),
        //HDMI output
        .gpdi_dp(gpdi_dp)
    );
    
	SuperResolutionSubTop m3 (    
		.clk_w(clk_25_out),
		.clk_r(clk_sdram),
		.rst_n(rst_n),
		.din(dout_sobel),
		.data_count_r_sobel(data_count_r_sobel),
		.rd_fifo(rd_sobel), 
		.rd_fifo_cam(rd_en_sobel),
		.dout(sobel_data),
		.data_count_r(data_count_sobel), 
		.frame_done(frame_done),  // Add this signal
		.led_s(led_s)
	);
     
    debounce_explicit m5 (
        .clk(clk_25_out),
        .rst_n(rst_n),
        .sw({key[0]}),
        .db_level(),
        .db_tick(key1_tick)
    );
     
    debounce_explicit m6 (
        .clk(clk_25_out),
        .rst_n(rst_n),
        .sw({key[1]}),
        .db_level(),
        .db_tick(key2_tick)
    );
     
    debounce_explicit m7 (
        .clk(clk_25_out), 
        .rst_n(rst_n),
        .sw({key[2]}),
        .db_level(),
        .db_tick(key3_tick)
    );

endmodule