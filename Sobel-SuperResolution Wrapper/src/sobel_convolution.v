module SuperResolutionSubTop(
    input wire clk_w, clk_r, rst_n,
    input wire [16:0] din,
    input wire [9:0] data_count_r_sobel,
    input wire rd_fifo,
    output reg rd_en,
    output reg rd_fifo_cam,
    output wire [16:0] dout,
    output wire [9:0] data_count_r,
    
);

    reg [16:0] pixel_data;
    reg write_fifo;

    always @(posedge clk_w or negedge rst_n) begin
        if (!rst_n) begin
            rd_en <= 0;
            rd_fifo_cam <= 0;
            pixel_data <= 0;
            write_fifo <= 0;
        end else begin
            if (data_count_r_sobel > 5) begin
                rd_en <= 1;
                rd_fifo_cam <= 1;
                pixel_data <= din;
                write_fifo <= 1;
            end else begin
                rd_en <= 0;
                rd_fifo_cam <= 0;
                write_fifo <= 0;
            end
        end
    end

    // Unused SDRAM interface
    always @* begin
        sdram_wr_req = 0;
        sdram_rd_req = 0;
        sdram_addr = 0;
        sdram_data_out = 0;
    end

    asyn_fifo #(
        .DATA_WIDTH(17),
        .FIFO_DEPTH_WIDTH(10)
    ) output_fifo (
        .rst_n(rst_n),
        .clk_write(clk_w),
        .clk_read(clk_r),
        .write(write_fifo),
        .read(rd_fifo),
        .data_write(pixel_data),
        .data_read(dout),
        .full(),
        .empty(),
        .data_count_w(),
        .data_count_r(data_count_r)
    );

endmodule