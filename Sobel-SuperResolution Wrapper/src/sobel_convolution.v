`timescale 1ns / 1ps

module sobel_convolution(
	input wire clk_w, clk_r, rst_n,
	input wire[16:0] din, // data from camera FIFO (16-bit color data)
	input wire[9:0] data_count_r_sobel, // camera FIFO data count
	input wire rd_fifo, // SDRAM interface will now start retrieving data from async FIFO
	output reg rd_en, // read camera FIFO
	output reg rd_fifo_cam,
	output wire[16:0] dout, // data to be stored in SDRAM
	output wire[9:0] data_count_r // Sobel FIFO data count
);

	// FSM for combining the kernels which will then be stored in async FIFO
	localparam init = 0, loop = 1;
	
	reg state_q, state_d;
	reg signed[9:0] temp1_q_r, temp2_q_r, temp3_q_r; // Buffers for Red channel
	reg signed[9:0] temp1_q_g, temp2_q_g, temp3_q_g; // Buffers for Green channel
	reg signed[9:0] temp1_q_b, temp2_q_b, temp3_q_b; // Buffers for Blue channel
	reg[10:0] pixel_counter_q = 1920;
	reg first_line, second_line, third_line;
	reg we_1, we_2, we_3, we_4, we_5, we_6;
	reg signed[7:0] din_ram_x_r, din_ram_y_r;
	reg signed[7:0] din_ram_x_g, din_ram_y_g;
	reg signed[7:0] din_ram_x_b, din_ram_y_b;
	reg[9:0] addr_a_x, addr_a_y, addr_b_q, addr_b_d;
	reg write;
	reg[16:0] data_write;
	reg signed[7:0] x_r, y_r, x_g, y_g, x_b, y_b;
	
	wire temp_valid;
	wire[12:0] gray; // Not used, but left here in case you want to maintain grayscale processing alongside color
	wire signed[7:0] dout_1, dout_2, dout_3, dout_4, dout_5, dout_6;
	wire data_available = data_count_r_sobel != 10'd0 && data_count_r_sobel != 10'd1 && data_count_r_sobel != 10'd2 && data_count_r_sobel != 10'd3 && data_count_r_sobel != 10'd4 && data_count_r_sobel != 10'd5;

	// Register operation
	always @(posedge clk_w, negedge rst_n) begin
		if (!rst_n) begin
			temp1_q_r <= 0;
			temp2_q_r <= 0;
			temp3_q_r <= 0;
			temp1_q_g <= 0;
			temp2_q_g <= 0;
			temp3_q_g <= 0;
			temp1_q_b <= 0;
			temp2_q_b <= 0;
			temp3_q_b <= 0;
			state_q <= 0;
			pixel_counter_q <= 1920;
			addr_b_q <= 0;
		end else begin
			state_q <= state_d;
			rd_en = 0;
			addr_b_q <= addr_b_d;
			rd_fifo_cam = 0;
			if (data_available) begin // Grouping every three pixels for the kernel convolution
				temp1_q_r <= {3'b000, din[15:11]}; // Red channel
				temp2_q_r <= temp1_q_r;
				temp3_q_r <= temp2_q_r;
				
				temp1_q_g <= {2'b00, din[10:5]}; // Green channel
				temp2_q_g <= temp1_q_g;
				temp3_q_g <= temp2_q_g;
				
				temp1_q_b <= {3'b000, din[4:0]}; // Blue channel
				temp2_q_b <= temp1_q_b;
				temp3_q_b <= temp2_q_b;

				pixel_counter_q <= (pixel_counter_q == 1919 || pixel_counter_q == 1920) ? 0 : pixel_counter_q + 1'b1; // 3 lines of pixel(640*3=1920)
				rd_en = 1;
				rd_fifo_cam = 1;
			end
		end
	end

	// Convolution pipeline logic for each color channel
	always @* begin
		we_1 = 0;
		we_2 = 0;
		we_3 = 0;
		we_4 = 0;
		we_5 = 0;
		we_6 = 0;

		din_ram_x_r = 0; din_ram_y_r = 0;
		din_ram_x_g = 0; din_ram_y_g = 0;
		din_ram_x_b = 0; din_ram_y_b = 0;
		addr_a_x = 0;
		addr_a_y = 0;

		if (pixel_counter_q != 1920) begin // Data is now ready for convolution
			if (first_line) begin // Convolution for the first row of the 3x3 kernel
				we_1 = 1;
				addr_a_y = pixel_counter_q;
				we_4 = 1;
				addr_a_x = pixel_counter_q;
			end else if (second_line) begin // Convolution for the second row of the 3x3 kernel
				we_2 = 1;
				addr_a_y = pixel_counter_q - 640;
				we_5 = 1;
				addr_a_x = pixel_counter_q - 640;
			end else if (third_line) begin // Convolution for the third row of the 3x3 kernel
				we_3 = 1;
				addr_a_y = pixel_counter_q - 1280;
				we_6 = 1;
				addr_a_x = pixel_counter_q - 1280;
			end
			
			din_ram_y_r = temp1_q_r + temp2_q_r + temp3_q_r; // Y kernel for Red
			din_ram_x_r = -temp3_q_r + temp1_q_r; // X kernel for Red
			
			din_ram_y_g = temp1_q_g + temp2_q_g + temp3_q_g; // Y kernel for Green
			din_ram_x_g = -temp3_q_g + temp1_q_g; // X kernel for Green
			
			din_ram_y_b = temp1_q_b + temp2_q_b + temp3_q_b; // Y kernel for Blue
			din_ram_x_b = -temp3_q_b + temp1_q_b; // X kernel for Blue
		end
	end

	// Finalize convolution by combining both kernels for each channel then store the result in async FIFO
	always @* begin
		write = 0;
		data_write = 0;
		x_r = 0; y_r = 0;
		x_g = 0; y_g = 0;
		x_b = 0; y_b = 0;
		addr_b_d = addr_b_q;
		state_d = state_q;

		case (state_q)
			init: if (pixel_counter_q == 0 && data_available) begin // No data yet
						addr_b_d = 0;
						state_d = loop;			
					end
			loop: if (data_available) begin
						addr_b_d = pixel_counter_q;
						if (first_line) begin
							addr_b_d = addr_b_d;
							y_r = dout_1 - dout_2; // Convolution result for Y kernel Red
							y_g = dout_1 - dout_2; // Convolution result for Y kernel Green
							y_b = dout_1 - dout_2; // Convolution result for Y kernel Blue
						end else if (second_line) begin
							addr_b_d = addr_b_d - 640;
							y_r = dout_2 - dout_3; // Convolution result for Y kernel Red
							y_g = dout_2 - dout_3; // Convolution result for Y kernel Green
							y_b = dout_2 - dout_3; // Convolution result for Y kernel Blue
						end else if (third_line) begin
							addr_b_d = addr_b_d - 1280;
							y_r = dout_3 - dout_1; // Convolution result for Y kernel Red
							y_g = dout_3 - dout_1; // Convolution result for Y kernel Green
							y_b = dout_3 - dout_1; // Convolution result for Y kernel Blue
						end
						
						x_r = dout_4 + dout_5 + dout_6; // Convolution result for X kernel Red
						x_g = dout_4 + dout_5 + dout_6; // Convolution result for X kernel Green
						x_b = dout_4 + dout_5 + dout_6; // Convolution result for X kernel Blue
						
						write = 1;
						
						if (x_r[7]) x_r = ~x_r; // Get absolute value of x since convolution result CAN BE NEGATIVE
						if (y_r[7]) y_r = ~y_r; // Get absolute value of y since convolution result CAN BE NEGATIVE 
						if (x_g[7]) x_g = ~x_g;
						if (y_g[7]) y_g = ~y_g;
						if (x_b[7]) x_b = ~x_b;
						if (y_b[7]) y_b = ~y_b;
						
						data_write = {din[16], x_r + y_r, x_g + y_g, x_b + y_b}; // Combine the results and store in RGB format
						
					end
		default: state_d = init;
		endcase 
	end

	always @* begin // Determines which pixel line the next data will be stored
		first_line = 0;
		second_line = 0; 
		third_line = 0;
		if (pixel_counter_q <= 639) first_line = 1;
		else if (pixel_counter_q <= 1279) second_line = 1;
		else if (pixel_counter_q <= 1919) third_line = 1;
	end

	// Module instantiations for processing each line
	dual_port_sync #(.ADDR_WIDTH(10) , .DATA_WIDTH(8)) m0 // Matrix Y convolution row 1 
	(
		.clk_r(clk_w),
		.clk_w(clk_w),
		.we(we_1),
		.din(din_ram_y_r),
		.addr_a(addr_a_y), // Write address
		.addr_b(addr_b_d), // Read address 
		.dout(dout_1)
	);
	
	dual_port_sync #(.ADDR_WIDTH(10) , .DATA_WIDTH(8)) m1 // Matrix Y convolution row 2
	(
		.clk_r(clk_w),
		.clk_w(clk_w),
		.we(we_2),
		.din(din_ram_y_r),
		.addr_a(addr_a_y), // Write address
		.addr_b(addr_b_d), // Read address 
		.dout(dout_2)
	);
	
	dual_port_sync #(.ADDR_WIDTH(10) , .DATA_WIDTH(8)) m2 // Matrix Y convolution row 3
	(
		.clk_r(clk_w),
		.clk_w(clk_w),
		.we(we_3),
		.din(din_ram_y_r),
		.addr_a(addr_a_y), // Write address
		.addr_b(addr_b_d), // Read address
		.dout(dout_3)
	);
	
	dual_port_sync #(.ADDR_WIDTH(10) , .DATA_WIDTH(8)) m3 // Matrix X convolution row 1
	(
		.clk_r(clk_w),
		.clk_w(clk_w),
		.we(we_4),
		.din(din_ram_x_r),
		.addr_a(addr_a_x), // Write address
		.addr_b(addr_b_d), // Read address 
		.dout(dout_4)
	);
	
	dual_port_sync #(.ADDR_WIDTH(10) , .DATA_WIDTH(8)) m4  // Matrix X convolution row 2
	(
		.clk_r(clk_w),
		.clk_w(clk_w),
		.we(we_5),
		.din(din_ram_x_r),
		.addr_a(addr_a_x), // Write address
		.addr_b(addr_b_d), // Read address ,addr_b is already buffered inside this module so we will use the "_d" ptr to advance the data(not "_q")
		.dout(dout_5)
	);
	
	dual_port_sync #(.ADDR_WIDTH(10) , .DATA_WIDTH(8)) m5  // Matrix X convolution row 3
	(
		.clk_r(clk_w),
		.clk_w(clk_w),
		.we(we_6),
		.din(din_ram_x_r),
		.addr_a(addr_a_x), // Write address
		.addr_b(addr_b_d), // Read address ,addr_b is already buffered inside this module so we will use the "_d" ptr to advance the data(not "_q")
		.dout(dout_6)
	);
	
	asyn_fifo #(.DATA_WIDTH(17), .FIFO_DEPTH_WIDTH(10)) m6 // 1024x17 FIFO mem
	(
		.rst_n(rst_n),
		.clk_write(clk_w),
		.clk_read(clk_r),
		.write(write),
		.read(rd_fifo), 
		.data_write(data_write), // Input FROM write clock domain
		.data_read(dout), // Output TO read clock domain
		.full(),
		.empty(), // full=sync to write domain clk , empty=sync to read domain clk
		.data_count_r(data_count_r) 
	);
endmodule

