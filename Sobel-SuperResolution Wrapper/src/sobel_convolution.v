module SuperResolutionSubTop(
    input wire clk_w, clk_r, rst_n,
    input wire [16:0] din,
    input wire [9:0] data_count_r_sobel,
    input wire rd_fifo,
    output reg rd_en,
    output reg rd_fifo_cam,
    output wire [16:0] dout,
    output wire [9:0] data_count_r
);
    localparam FRAME_SIZE = 76800; // 320x240 pixels

    reg [1:0] state_q, state_d;
    reg [16:0] pixel_q, pixel_d;
    reg [9:0] pixel_counter_q = 320;
    reg [4:0] r_channel;
    reg [5:0] g_channel;
    reg [4:0] b_channel;
    reg [16:0] data_write;
    reg write;
    wire data_available = data_count_r_sobel > 5;

    // Frame sync
    reg frame_sync;
    reg [7:0] line_counter;

    // Signals for dual_port_sync modules
    reg we_1, we_2, we_3, we_4, we_5, we_6;
    reg signed [7:0] din_ram_x, din_ram_y;
    reg [8:0] addr_a_x, addr_a_y, addr_b_q, addr_b_d;
    wire signed [7:0] dout_1, dout_2, dout_3, dout_4, dout_5, dout_6;

    // Double buffering
    reg current_buffer;
    reg [16:0] frame_buffer_1[0:FRAME_SIZE-1];
    reg [16:0] frame_buffer_2[0:FRAME_SIZE-1];
    reg frame_complete;

    always @(posedge clk_w or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= 0;
            pixel_counter_q <= 320;
            rd_en <= 1'b0;
            rd_fifo_cam <= 1'b0;
            frame_sync <= 1'b0;
            line_counter <= 0;
            current_buffer <= 0;
            frame_complete <= 0;
            pixel_q <= 0;
        end else begin
            state_q <= state_d;
            rd_en <= 1'b0;
            rd_fifo_cam <= 1'b0;
            if (data_available) begin
                r_channel <= din[15:11];
                g_channel <= din[10:5];
                b_channel <= din[4:0];
                rd_en <= 1'b1;
                rd_fifo_cam <= 1'b1;
                
                if (pixel_counter_q == 319) begin
                    pixel_counter_q <= 0;
                    if (line_counter == 239) begin
                        line_counter <= 0;
                        frame_sync <= ~frame_sync;
                        current_buffer <= ~current_buffer;
                        frame_complete <= 1;
                    end else begin
                        line_counter <= line_counter + 1;
                    end
                end else begin
                    pixel_counter_q <= pixel_counter_q + 1'b1;
                end

                // Store in the current buffer
                if (current_buffer == 0)
                    frame_buffer_1[line_counter * 320 + pixel_counter_q] <= din;
                else
                    frame_buffer_2[line_counter * 320 + pixel_counter_q] <= din;
            end
        end
    end

    // Simplified convolution logic (for debugging)
    always @* begin
        we_1 = 0; we_2 = 0; we_3 = 0; we_4 = 0; we_5 = 0; we_6 = 0;
        din_ram_x = 0; din_ram_y = 0;
        addr_a_x = 0; addr_a_y = 0;
        
        if (pixel_counter_q != 320) begin
            we_1 = 1; we_4 = 1;
            addr_a_y = pixel_counter_q;
            addr_a_x = pixel_counter_q;
            din_ram_y = {3'b0, r_channel};
            din_ram_x = {2'b0, g_channel};
        end
    end

    always @* begin
        write = 0;
        data_write = 0;
        addr_b_d = addr_b_q;
        state_d = state_q;

        case (state_q)
            2'b00: if (frame_complete) begin
                addr_b_d = 0;
                state_d = 2'b01;            
            end
            2'b01: if (rd_fifo) begin
                addr_b_d = (addr_b_q == FRAME_SIZE - 1) ? 0 : addr_b_q + 1;
                write = 1;
                // Read from the non-current buffer
                data_write = current_buffer ? frame_buffer_1[addr_b_q] : frame_buffer_2[addr_b_q];
            end
            default: state_d = 2'b00;
        endcase 
    end

    // Dual port sync modules
    dual_port_sync #(.ADDR_WIDTH(9), .DATA_WIDTH(8)) m0 (
        .clk_r(clk_w), .clk_w(clk_w), .we(we_1),
        .din(din_ram_y), .addr_a(addr_a_y), .addr_b(addr_b_d), .dout(dout_1)
    );
    
    dual_port_sync #(.ADDR_WIDTH(9), .DATA_WIDTH(8)) m1 (
        .clk_r(clk_w), .clk_w(clk_w), .we(we_2),
        .din(din_ram_y), .addr_a(addr_a_y), .addr_b(addr_b_d), .dout(dout_2)
    );
    
    dual_port_sync #(.ADDR_WIDTH(9), .DATA_WIDTH(8)) m2 (
        .clk_r(clk_w), .clk_w(clk_w), .we(we_3),
        .din(din_ram_y), .addr_a(addr_a_y), .addr_b(addr_b_d), .dout(dout_3)
    );
    
    dual_port_sync #(.ADDR_WIDTH(9), .DATA_WIDTH(8)) m3 (
        .clk_r(clk_w), .clk_w(clk_w), .we(we_4),
        .din(din_ram_x), .addr_a(addr_a_x), .addr_b(addr_b_d), .dout(dout_4)
    );
    
    dual_port_sync #(.ADDR_WIDTH(9), .DATA_WIDTH(8)) m4 (
        .clk_r(clk_w), .clk_w(clk_w), .we(we_5),
        .din(din_ram_x), .addr_a(addr_a_x), .addr_b(addr_b_d), .dout(dout_5)
    );
    
    dual_port_sync #(.ADDR_WIDTH(9), .DATA_WIDTH(8)) m5 (
        .clk_r(clk_w), .clk_w(clk_w), .we(we_6),
        .din(din_ram_x), .addr_a(addr_a_x), .addr_b(addr_b_d), .dout(dout_6)
    );
    
    asyn_fifo #(.DATA_WIDTH(17), .FIFO_DEPTH_WIDTH(10)) m6 (
        .rst_n(rst_n), .clk_write(clk_w), .clk_read(clk_r),
        .write(write), .read(rd_fifo), 
        .data_write(data_write), .data_read(dout),
        .full(), .empty(), .data_count_r(data_count_r) 
    );

endmodule