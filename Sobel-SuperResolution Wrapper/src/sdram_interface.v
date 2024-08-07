`timescale 1ns / 1ps

module sdram_interface(
    input clk, rst_n, // clk is 143MHz (SDRAM)
    // fifo for camera
    input wire clk_vga, rd_en,
    input wire sobel,
    input wire [9:0] data_count_camera_fifo, // number of data in camera fifo
    input wire [16:0] din, // data from camera fifo
    output wire rd_camera, // read camera fifo
    // sobel
    input wire [16:0] sobel_data,
    input wire [9:0] data_count_r,
    output wire rd_sobel,
    // fifo for vga
    output wire empty_fifo, 
    output wire [15:0] dout,
    // controller to sdram
    output wire sdram_clk,
    output wire sdram_cke,  
    output wire sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n, 
    output wire [12:0] sdram_addr,
    output wire [1:0] sdram_ba, 
    output wire [1:0] sdram_dqm, 
    inout wire [15:0] sdram_dq
);
    // FSM state declarations
    localparam idle = 0,
               burst_op = 1;
               
    reg state_q = 0, state_d;     
    reg [14:0] sobel_addr_q = 0, sobel_addr_d;
    reg [14:0] rd_addr_q = 0, rd_addr_d;
    reg rw, rw_en;
    reg orig_q = 0, orig_d;
    reg [14:0] f_addr;
    wire [15:0] s2f_data;
    wire s2f_data_valid, f2s_data_valid;
    wire ready;
    wire [9:0] data_count_w;
    reg [15:0] f2s_data;
     
    // Register operation
    always @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            state_q <= idle;
            sobel_addr_q <= 0;
            rd_addr_q <= 0;
            orig_q <= 0;
        end else begin
            state_q <= state_d;
            sobel_addr_q <= sobel_addr_d;
            rd_addr_q <= rd_addr_d;
            orig_q <= orig_d;
        end
    end
     
    // FSM next-state declarations
    always @* begin
        state_d = state_q;
        sobel_addr_d = sobel_addr_q;
        rd_addr_d = rd_addr_q;
        f_addr = 0;
        rw = 0;
        rw_en = 0;
        orig_d = orig_q;
        
        case (state_q)
            idle: if (data_count_r > 512 && ready) begin // Wait for the first 512 pixel-data to fill the asyn_fifo then burst-write it to sdram
                    rw_en = 1;
                    rw = 0;
                    sobel_addr_d = 1;
					sobel_addr_d_2 = 600;
                    f_addr = sobel_addr_q;
                    state_d = burst_op;
                    orig_d = 1;
                  end
            burst_op: if (ready) begin // Handle Sobel data only
                        if (data_count_r > 512) begin // Sobel data is ready, burst-write to SDRAM
                            rw_en = 1;
                            rw = 0;
                            sobel_addr_d = (sobel_addr_q == 599) ? 0 : sobel_addr_q + 1'b1; // Adjusted address range for Sobel output
                            f_addr = sobel_addr_q;
                            orig_d = 1;
                        end else if (data_count_w < 250) begin // asyn_fifo of VGA has only 250 pixel data left, we will now fill it by another 512 pixel data via burst reading the sdram
                            rw_en = 1;
                            rw = 1;
                            rd_addr_d = (rd_addr_q == 599) ? 0 : rd_addr_q + 1'b1;
                            f_addr = rd_addr_q;
                        end
						// else if (data_count_r>512) begin
                        //     rw_en = 1;
                        //     rw = 0;
                        //     sobel_addr_d_2 = (sobel_addr_q == 1199) ? 600 : sobel_addr_q + 1'b1; // Adjusted address range for Sobel output
                        //     f_addr = sobel_addr_q;
                        //     orig_d = 0;
						//end
                      end
            default: state_d=idle;
        endcase

        // Convert the 8-bit Sobel output to 16-bit color (simple mapping)
		f2s_data ={sobel_data[15:0]};;// {1'b0, sobel_data[15:12],1'b0, sobel_data[10:7],1'b0, sobel_data[4:1]};//(sobel_data[16]? 16'b00000_00000_11111 : sobel_data[15:0]);
    end
 
    // Unused inputs/outputs are managed to prevent synthesis issues
	 assign rd_camera= f2s_data_valid && orig_d;
	 assign rd_sobel= f2s_data_valid && orig_d;
     
    // Module instantiations
    sdram_controller m0 (
        // fpga to controller
        .clk(clk), // clk = 143MHz
        .rst_n(rst_n),  
        .rw(rw), // 1: read, 0: write
        .rw_en(rw_en), // must be asserted before read/write
        .f_addr(f_addr), // 14:2 = row (13), 1:0 = bank (2), no need for column address since full page mode will always start from zero and end with 511 words
        .f2s_data(f2s_data), // fpga-to-sdram data
        .s2f_data(s2f_data), // sdram to fpga data
        .s2f_data_valid(s2f_data_valid),  // asserts while burst-reading (data is available at output UNTIL the next rising edge)
        .f2s_data_valid(f2s_data_valid), // asserts while burst-writing (data must be available at input BEFORE the next rising edge)
        .ready(ready), // "1" if sdram is available for next read/write operation
        // controller to sdram
        .s_clk(sdram_clk),
        .s_cke(sdram_cke), 
        .s_cs_n(sdram_cs_n),
        .s_ras_n(sdram_ras_n), 
        .s_cas_n(sdram_cas_n),
        .s_we_n(sdram_we_n), 
        .s_addr(sdram_addr), 
        .s_ba(sdram_ba), 
        .LDQM(sdram_dqm[0]),
        .HDQM(sdram_dqm[1]),
        .s_dq(sdram_dq)
    ); 
    
    asyn_fifo #(.DATA_WIDTH(20), .FIFO_DEPTH_WIDTH(10)) m2 // 1024x16 FIFO mem, FIFO_DEPTH = 10
    (
        .rst_n(rst_n),
        .clk_write(clk),
        .clk_read(clk_vga),
        .write(s2f_data_valid),
        .read(rd_en), 
        .data_write(s2f_data), // input FROM write clock domain
        .data_read(dout), // output TO read clock domain
        .full(),
        .empty(empty_fifo), // full = sync to write domain clk, empty = sync to read domain clk
        .data_count_w(data_count_w) 
    );
    
endmodule
