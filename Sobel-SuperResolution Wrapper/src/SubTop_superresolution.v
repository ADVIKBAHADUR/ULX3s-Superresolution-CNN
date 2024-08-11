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
        .bram_addr(4'b0),
        .start_process(state == PROCESS),
        .x_in(process_addr % WIDTH),
        .y_in(process_addr / WIDTH),
        .pixel_out(processed_pixel),
        .process_done(process_done),
        .debug_leds(superres)
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
        end else begin
            state <= next_state;
            write_addr <= next_write_addr;
            process_addr <= next_process_addr;
            processing_done <= next_processing_done;
            write_fifo <= next_write_fifo;
            pixel_data <= next_pixel_data;
            frame_capture_complete <= next_frame_capture_complete;

            debug_counter <= debug_counter + 1;

            // Simplified data handling logic
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

            // LED indicators
            led_subtop[0] <= (state == IDLE ? 1 :(state == CAPTURE ? 0 : (state == PROCESS ? 1 : (state == WAIT_PROCESS ? 1 : (state == OUTPUT)))));
            led_subtop[1] <= (state == IDLE ? 0 :(state == CAPTURE ? 1 : (state == PROCESS ? 1 : (state == WAIT_PROCESS ? 0 : (state == OUTPUT)))));
            led_subtop[2] <= (state == IDLE ? 0 :(state == CAPTURE ? 0 : (state == PROCESS ? 0 : (state == WAIT_PROCESS ? 1 : (state == OUTPUT)))));
            led_subtop[3] <= (data_received_counter > 0);
            led_subtop[4] <= frame_capture_complete;
            led_subtop[5] <= (write_addr >= 76799);
            led_subtop[6] <= (data_count_r_sobel > 5);
            led_subtop[7] <= (process_done);  
            
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
                    end
                end
            end

            PROCESS: begin
                if (process_done) begin
                    next_pixel_data = processed_pixel;
                    next_write_fifo = 1;
                    next_process_addr = process_addr + 1;
                    if (process_addr >= FRAME_SIZE - 1) begin
                        next_processing_done = 1;
                        next_state = OUTPUT;
                    end
                end
            end

            WAIT_PROCESS: begin
                // This state might not be needed anymore
                next_state = PROCESS;
            end

            OUTPUT: begin
                next_write_fifo = 0;
                if (0 == 0) begin
                    next_state = IDLE;
                    next_processing_done = 0;
                end
            end
        endcase
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