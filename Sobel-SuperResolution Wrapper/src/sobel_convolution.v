module sobel_convolution(
    input wire clk_w, clk_r, rst_n,
    input wire [16:0] din,
    input wire [9:0] data_count_r_sobel,
    input wire rd_fifo,
    output reg rd_en,
    output reg rd_fifo_cam,
    output wire [16:0] dout,
    output wire [9:0] data_count_r
);
    localparam init = 0, loop = 1;
    reg state_q, state_d;
    reg [10:0] pixel_counter_q = 1920;
    reg [44:0] r_channel; // 9 * 5 bits
    reg [53:0] g_channel; // 9 * 6 bits
    reg [44:0] b_channel; // 9 * 5 bits
    reg [23:0] data_write;  // Changed to 24 bits to preserve full color
    reg write;
    reg start_super_res;
    wire super_res_done;
    wire [23:0] super_res_out;
    wire data_available = data_count_r_sobel > 5;

    // Calculate x and y coordinates
    wire [10:0] x_coord = pixel_counter_q % 640;
    wire [10:0] y_coord = pixel_counter_q / 640;

    // Superresolution module instance
    superresolution super_res (
        .clk(clk_w),
        .rst_n(rst_n),
        .pixel_in({r_channel[22:15], g_channel[26:19], b_channel[22:15]}),
        .start_process(start_super_res),
        .x_in(x_coord),
        .y_in(y_coord),
        .pixel_out(super_res_out),
        .process_done(super_res_done)
    );

    always @(posedge clk_w or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= init;
            pixel_counter_q <= 1920;
            r_channel <= 45'd0;
            g_channel <= 54'd0;
            b_channel <= 45'd0;
            rd_en <= 1'b0;
            rd_fifo_cam <= 1'b0;
            start_super_res <= 1'b0;
        end else begin
            state_q <= state_d;
            rd_en <= 1'b0;
            rd_fifo_cam <= 1'b0;
            start_super_res <= 1'b0;
            if (data_available) begin
                r_channel <= {r_channel[39:0], din[15:11]};
                g_channel <= {g_channel[47:0], din[10:5]};
                b_channel <= {b_channel[39:0], din[4:0]};
                rd_en <= 1'b1;
                rd_fifo_cam <= 1'b1;
                pixel_counter_q <= (pixel_counter_q == 1919) ? 0 : pixel_counter_q + 1'b1;
                if (pixel_counter_q == 1919) begin
                    start_super_res <= 1'b1;
                end
            end
        end
    end

    always @(posedge clk_w or negedge rst_n) begin
        if (!rst_n) begin
            state_d <= init;
            data_write <= 24'b0;
            write <= 1'b0;
        end else begin
            case (state_q)
                init: if (pixel_counter_q == 0 && data_available) begin
                    state_d <= loop;
                end
                loop: begin
                    // Preserve full 24-bit color output from superresolution
                    data_write <= super_res_out;
                    write <= 1'b1;
                    if (super_res_done) begin
                        state_d <= init;
                    end
                end
                default: state_d <= init;
            endcase
        end
    end

    // Modified FIFO to handle 24-bit color
    asyn_fifo #(.DATA_WIDTH(24), .FIFO_DEPTH_WIDTH(10)) output_fifo (
        .rst_n(rst_n),
        .clk_write(clk_w),
        .clk_read(clk_r),
        .write(write),
        .read(rd_fifo),
        .data_write(data_write),
        .data_read(dout),
        .full(),
        .empty(),
        .data_count_r(data_count_r)
    );
endmodule