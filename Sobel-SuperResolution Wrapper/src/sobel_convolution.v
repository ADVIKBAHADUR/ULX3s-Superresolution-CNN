module SuperResolutionSubTop #(
    parameter WIDTH = 320,
    parameter HEIGHT = 240,
    parameter PIXEL_WIDTH = 24,
    parameter WEIGHT_ADDR_WIDTH = 18
) (
    input wire clk_w, clk_r, rst_n,
    input wire [PIXEL_WIDTH-1:0] din,
    input wire [9:0] data_count_r_sobel,
    input wire rd_fifo,
    output reg rd_en,
    output reg rd_fifo_cam,
    output wire [PIXEL_WIDTH-1:0] dout,
    output wire [9:0] data_count_r,
    output wire frame_done
);

    localparam FRAME_ADDR_WIDTH = $clog2(WIDTH * HEIGHT);

    // State machine states
    localparam IDLE = 3'd0, CAPTURE = 3'd1, PROCESS = 3'd2, WAIT_PROCESS = 3'd3, OUTPUT = 3'd4, WAIT_FIFO = 3'd5;

    reg [2:0] state;
    reg [FRAME_ADDR_WIDTH-1:0] write_addr;
    reg [FRAME_ADDR_WIDTH-1:0] process_addr;
    reg processing_done;
    reg [PIXEL_WIDTH-1:0] pixel_data;
    reg write_fifo;

    // Frame buffer BRAM
    reg [PIXEL_WIDTH-1:0] frame_buffer_din;
    wire [PIXEL_WIDTH-1:0] frame_buffer_dout;
    reg frame_buffer_we;
    reg [FRAME_ADDR_WIDTH-1:0] frame_buffer_addr;

    // 3x3 neighborhood BRAM
    reg [PIXEL_WIDTH-1:0] neighborhood_bram [0:8];
    wire [PIXEL_WIDTH-1:0] processed_pixel;
    wire process_done;

    // Dual-port BRAM for frame buffer
    dual_port_bram #(
        .DATA_WIDTH(PIXEL_WIDTH),
        .ADDR_WIDTH(FRAME_ADDR_WIDTH)
    ) frame_buffer (
        .clka(clk_w),
        .clkb(clk_r),
        .ena(1'b1),
        .enb(1'b1),
        .wea(frame_buffer_we),
        .web(1'b0),
        .addra(frame_buffer_addr),
        .addrb(process_addr),
        .dia(frame_buffer_din),
        .dib({PIXEL_WIDTH{1'b0}}),
        .doa(),
        .dob(frame_buffer_dout)
    );

    // Superresolution instance
    superresolution #(
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
    ) sr_inst (
        .clk(clk_r),
        .rst_n(rst_n),
        .bram_addr(4'b0), // Always start from the beginning of neighborhood_bram
        .start_process(state == PROCESS),
        .x_in(process_addr % WIDTH),
        .y_in(process_addr / WIDTH),
        .pixel_out(processed_pixel),
        .process_done(process_done)
    );

    // Output FIFO
    asyn_fifo #(
        .DATA_WIDTH(PIXEL_WIDTH),
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

    always @(posedge clk_w or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            write_addr <= 0;
            process_addr <= 0;
            rd_en <= 0;
            rd_fifo_cam <= 0;
            processing_done <= 0;
            write_fifo <= 0;
            pixel_data <= 0;
            frame_buffer_we <= 0;
            frame_buffer_addr <= 0;
            frame_buffer_din <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (data_count_r_sobel > 5) begin
                        state <= CAPTURE;
                        write_addr <= 0;
                        rd_en <= 1;
                        rd_fifo_cam <= 1;
                    end
                end

                CAPTURE: begin
                    if (data_count_r_sobel > 0) begin
                        frame_buffer_din <= din;
                        frame_buffer_we <= 1;
                        frame_buffer_addr <= write_addr;
                        write_addr <= write_addr + 1;
                        if (write_addr == WIDTH*HEIGHT-1) begin
                            state <= PROCESS;
                            process_addr <= 0;
                            rd_en <= 0;
                            rd_fifo_cam <= 0;
                        end
                    end else begin
                        state <= WAIT_FIFO;
                        rd_en <= 0;
                        rd_fifo_cam <= 0;
                    end
                    frame_buffer_we <= 0;
                end

                WAIT_FIFO: begin
                    if (data_count_r_sobel > 5) begin
                        state <= CAPTURE;
                        rd_en <= 1;
                        rd_fifo_cam <= 1;
                    end
                end

                PROCESS: begin
                    // Load 3x3 neighborhood into BRAM
                    neighborhood_bram[0] <= (process_addr >= WIDTH + 1) ? frame_buffer_dout : frame_buffer_dout;
                    neighborhood_bram[1] <= (process_addr >= WIDTH) ? frame_buffer_dout : frame_buffer_dout;
                    neighborhood_bram[2] <= (process_addr >= WIDTH - 1) ? frame_buffer_dout : frame_buffer_dout;
                    neighborhood_bram[3] <= (process_addr % WIDTH != 0) ? frame_buffer_dout : frame_buffer_dout;
                    neighborhood_bram[4] <= frame_buffer_dout;
                    neighborhood_bram[5] <= (process_addr % WIDTH != WIDTH - 1) ? frame_buffer_dout : frame_buffer_dout;
                    neighborhood_bram[6] <= (process_addr < WIDTH * (HEIGHT - 1)) ? frame_buffer_dout : frame_buffer_dout;
                    neighborhood_bram[7] <= (process_addr < WIDTH * (HEIGHT - 1) + 1) ? frame_buffer_dout : frame_buffer_dout;
                    neighborhood_bram[8] <= (process_addr < WIDTH * HEIGHT - 1) ? frame_buffer_dout : frame_buffer_dout;
                    
                    state <= WAIT_PROCESS;
                end

                WAIT_PROCESS: begin
                    if (process_done) begin
                        pixel_data <= processed_pixel;
                        write_fifo <= 1;
                        process_addr <= process_addr + 1;
                        if (process_addr >= WIDTH*HEIGHT-1) begin
                            processing_done <= 1;
                            state <= OUTPUT;
                        end else begin
                            state <= PROCESS;
                        end
                    end
                end

                OUTPUT: begin
                    write_fifo <= 0;
                    if (data_count_r == 0) begin
                        state <= IDLE;
                        processing_done <= 0;
                    end
                end
            endcase
        end
    end

    assign frame_done = (state == IDLE) && processing_done;

endmodule

// Dual-port BRAM module
module dual_port_bram #(
    parameter DATA_WIDTH = 24,
    parameter ADDR_WIDTH = 18
) (
    input wire clka, clkb,
    input wire ena, enb,
    input wire wea, web,
    input wire [ADDR_WIDTH-1:0] addra, addrb,
    input wire [DATA_WIDTH-1:0] dia, dib,
    output reg [DATA_WIDTH-1:0] doa, dob
);

    reg [DATA_WIDTH-1:0] ram [0:(1<<ADDR_WIDTH)-1];

    always @(posedge clka) begin
        if (ena) begin
            if (wea)
                ram[addra] <= dia;
            doa <= ram[addra];
        end
    end

    always @(posedge clkb) begin
        if (enb) begin
            if (web)
                ram[addrb] <= dib;
            dob <= ram[addrb];
        end
    end

endmodule