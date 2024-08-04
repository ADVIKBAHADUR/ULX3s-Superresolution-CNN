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
    reg [10:0] pixel_counter_q;
    reg [8:0] r_channel[0:2][0:2];
    reg [8:0] g_channel[0:2][0:2];
    reg [8:0] b_channel[0:2][0:2];
    reg [16:0] data_write;
    wire data_available = data_count_r_sobel > 5;
    wire [7:0] model_output_r, model_output_g, model_output_b;

    neural_network_model model(
        .clk(clk_w),
        .reset(~rst_n),
        .r_channel(r_channel),
        .g_channel(g_channel),
        .b_channel(b_channel),
        .output_r(model_output_r),
        .output_g(model_output_g),
        .output_b(model_output_b)
    );

    always @(posedge clk_w or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= init;
            pixel_counter_q <= 11'd1920;
            for (int i = 0; i < 3; i++) begin
                for (int j = 0; j < 3; j++) begin
                    r_channel[i][j] <= 9'd0;
                    g_channel[i][j] <= 9'd0;
                    b_channel[i][j] <= 9'd0;
                end
            end
            rd_en <= 1'b0;
            rd_fifo_cam <= 1'b0;
        end else begin
            state_q <= state_d;
            rd_en <= 1'b0;
            rd_fifo_cam <= 1'b0;
            if (data_available) begin
                // Shift the window
                for (int i = 0; i < 2; i++) begin
                    for (int j = 0; j < 3; j++) begin
                        r_channel[i][j] <= r_channel[i+1][j];
                        g_channel[i][j] <= g_channel[i+1][j];
                        b_channel[i][j] <= b_channel[i+1][j];
                    end
                end
                for (int j = 0; j < 2; j++) begin
                    r_channel[2][j] <= r_channel[2][j+1];
                    g_channel[2][j] <= g_channel[2][j+1];
                    b_channel[2][j] <= b_channel[2][j+1];
                end
                // Load new pixel
                r_channel[2][2] <= din[15:11];
                g_channel[2][2] <= din[10:5];
                b_channel[2][2] <= din[4:0];
                rd_en <= 1'b1;
                rd_fifo_cam <= 1'b1;
                pixel_counter_q <= (pixel_counter_q == 11'd1919 || pixel_counter_q == 11'd1920) ? 11'd0 : pixel_counter_q + 1'b1;
            end
        end
    end

    always @(posedge clk_w or negedge rst_n) begin
        if (!rst_n) begin
            state_d <= init;
            data_write <= 17'd0;
        end else begin
            if (data_available) begin
                data_write <= {din[16], model_output_r[7:3], model_output_g[7:2], model_output_b[7:3]};
                state_d <= loop;
            end
        end
    end

    asyn_fifo #(.DATA_WIDTH(17), .FIFO_DEPTH_WIDTH(10)) m6 (
        .rst_n(rst_n),
        .clk_write(clk_w),
        .clk_read(clk_r),
        .write(state_d == loop),
        .read(rd_fifo),
        .data_write(data_write),
        .data_read(dout),
        .full(),
        .empty(),
        .data_count_r(data_count_r)
    );
endmodule
