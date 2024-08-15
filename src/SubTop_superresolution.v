module SuperResolutionSubTop #(
    parameter WIDTH = 320,
    parameter HEIGHT = 240,
    parameter PIXEL_WIDTH = 16,
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
    output wire frame_done,
    output reg [7:0] led_s
);

    localparam FRAME_ADDR_WIDTH = $clog2(WIDTH * HEIGHT);
    localparam FRAME_SIZE = WIDTH * HEIGHT;

    reg [7:0] led_subtop;
    reg [7:0] superres;

    assign led_s = led_subtop;

    // State machine states
    localparam IDLE = 3'd0, CAPTURE = 3'd1, PROCESS = 3'd2, WAIT_PROCESS = 3'd3, OUTPUT = 3'd4;

    reg [2:0] state, next_state;
    reg [31:0] write_addr, next_write_addr;
    reg [31:0] process_addr, next_process_addr;
    reg processing_done, next_processing_done;
    reg [PIXEL_WIDTH-1:0] pixel_data, next_pixel_data;
    reg write_fifo, next_write_fifo;
    reg frame_capture_complete, next_frame_capture_complete;

    // Debugging signals
    reg [31:0] debug_counter;
    reg [31:0] data_received_counter;
    wire [7:0] upsample_debug_leds;

    // Frame buffer BRAM
    reg [PIXEL_WIDTH-1:0] frame_buffer_din;
    wire [PIXEL_WIDTH-1:0] frame_buffer_dout;
    reg frame_buffer_we;
    reg [FRAME_ADDR_WIDTH-1:0] frame_buffer_addr;

    // 3x3 neighborhood buffer
    reg [9*PIXEL_WIDTH-1:0] neighborhood;

    // Superresolution control signals
    reg [8:0] bram_addr;
    reg start_process;
    wire pixel_done;
    wire [PIXEL_WIDTH-1:0] processed_pixel;

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
        .bram_addr(bram_addr),
        .start_process(start_process),
        .x_in(process_addr % WIDTH),
        .y_in(process_addr / WIDTH),
        .neighborhood(neighborhood),
        .pixel_out(processed_pixel),
        .pixel_done(pixel_done)
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

    // Sequential logic
    always @(posedge clk_w or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            write_addr <= 0;
            process_addr <= 0;
            processing_done <= 0;
            write_fifo <= 0;
            pixel_data <= 0;
            frame_buffer_we <= 0;
            frame_buffer_addr <= 0;
            frame_buffer_din <= 0;
            frame_capture_complete <= 0;
            debug_counter <= 0;
            data_received_counter <= 0;
            rd_en <= 0;
            rd_fifo_cam <= 0;
            led_subtop <= 8'b0;
            bram_addr <= 0;
            start_process <= 0;
            neighborhood <= 0;
        end else begin
            state <= next_state;
            write_addr <= next_write_addr;
            process_addr <= next_process_addr;
            processing_done <= next_processing_done;
            write_fifo <= next_write_fifo;
            pixel_data <= next_pixel_data;
            frame_capture_complete <= next_frame_capture_complete;

            debug_counter <= debug_counter + 1;

            if (state == PROCESS) begin
                start_process <= 1;
            end else begin
                start_process <= 0;
            end

            if (data_count_r_sobel > 5) begin
                rd_en <= 1;
                rd_fifo_cam <= 1;
                frame_buffer_din <= din;
                frame_buffer_we <= 1;
                frame_buffer_addr <= write_addr;
                data_received_counter <= data_received_counter + 1;
            end else begin
                rd_en <= 0;
                rd_fifo_cam <= 0;
                frame_buffer_we <= 0;
            end

            if (state == PROCESS) begin
                neighborhood[0*PIXEL_WIDTH +: PIXEL_WIDTH] <= (process_addr % WIDTH == 0 || process_addr < WIDTH) ? 24'h0 : frame_buffer_dout;
                neighborhood[1*PIXEL_WIDTH +: PIXEL_WIDTH] <= (process_addr < WIDTH) ? 24'h0 : frame_buffer_dout;
                neighborhood[2*PIXEL_WIDTH +: PIXEL_WIDTH] <= (process_addr % WIDTH == WIDTH - 1 || process_addr < WIDTH) ? 24'h0 : frame_buffer_dout;
                neighborhood[3*PIXEL_WIDTH +: PIXEL_WIDTH] <= (process_addr % WIDTH == 0) ? 24'h0 : frame_buffer_dout;
                neighborhood[4*PIXEL_WIDTH +: PIXEL_WIDTH] <= frame_buffer_dout;
                neighborhood[5*PIXEL_WIDTH +: PIXEL_WIDTH] <= (process_addr % WIDTH == WIDTH - 1) ? 24'h0 : frame_buffer_dout;
                neighborhood[6*PIXEL_WIDTH +: PIXEL_WIDTH] <= (process_addr % WIDTH == 0 || process_addr >= (HEIGHT - 1) * WIDTH) ? 24'h0 : frame_buffer_dout;
                neighborhood[7*PIXEL_WIDTH +: PIXEL_WIDTH] <= (process_addr >= (HEIGHT - 1) * WIDTH) ? 24'h0 : frame_buffer_dout;
                neighborhood[8*PIXEL_WIDTH +: PIXEL_WIDTH] <= (process_addr % WIDTH == WIDTH - 1 || process_addr >= (HEIGHT - 1) * WIDTH) ? 24'h0 : frame_buffer_dout;
            end

            // LED indicators
            led_subtop[0] <= (state == IDLE ? 1 : (state = OUTPUT ? 1: 0));
            led_subtop[1] <= (state == CAPTURE ? 1 : (state = OUTPUT ? 1: 0));
            led_subtop[2] <= (state == PROCESS ? 1 : (state = OUTPUT ? 1: 0));
            led_subtop[3] <= pixel_done;
            led_subtop[4] <= (pixel_data == 24'h000000); // New check for black pixels
            led_subtop[5] <= (write_addr >= 76799);
            led_subtop[6] <= (data_count_r_sobel > 5);
            led_subtop[7] <= processing_done;
        end
    end

    // Combinational logic
    always @* begin
        next_state = state;
        next_write_addr = write_addr;
        next_process_addr = process_addr;
        next_processing_done = processing_done;
        next_write_fifo = write_fifo;
        next_pixel_data = pixel_data;
        next_frame_capture_complete = frame_capture_complete;

        case (state)
            IDLE: begin
                if (data_count_r_sobel > 5) begin
                    next_state = CAPTURE;
                    next_write_addr = 0;
                    next_frame_capture_complete = 0;
                end
            end

            CAPTURE: begin
                if (data_count_r_sobel > 5) begin
                    next_write_addr = write_addr + 1;
                    if (write_addr >= FRAME_SIZE - 1) begin
                        next_frame_capture_complete = 1;
                        next_state = PROCESS;
                        next_process_addr = 0;
                        bram_addr = 0;
                    end
                end
            end

            PROCESS: begin
                if (pixel_done) begin
                    next_pixel_data = processed_pixel;
                    next_write_fifo = 1;
                    next_process_addr = process_addr + 1;
                    bram_addr = bram_addr + 1;
                    if (process_addr >= FRAME_SIZE - 1) begin
                        next_processing_done = 1;
                        next_state = OUTPUT;
                    end
                end
            end

            WAIT_PROCESS: begin
                next_state = PROCESS;
            end

            OUTPUT: begin
                next_write_fifo = 0;
                next_state = IDLE;
                next_processing_done = 0;
                // if (debug_counter[10]) begin
                //     next_state = IDLE;
                //     next_processing_done = 0;
                // end
            end
        endcase
    end

    assign frame_done = (state == IDLE) && processing_done;

endmodule