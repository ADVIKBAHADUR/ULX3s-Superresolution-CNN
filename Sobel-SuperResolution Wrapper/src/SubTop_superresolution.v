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

    // State machine states
    localparam IDLE = 3'd0, CAPTURE = 3'd1, PROCESS = 3'd2, WAIT_PROCESS = 3'd3, OUTPUT = 3'd4;

    reg [2:0] state, next_state;
    reg [31:0] write_addr, next_write_addr;
    reg [31:0] process_addr, next_process_addr;
    reg processing_done, next_processing_done;
    reg [PIXEL_WIDTH-1:0] pixel_data, next_pixel_data;
    reg write_fifo, next_write_fifo;
    reg frame_capture_complete, next_frame_capture_complete;
    reg frame_being_processed, next_frame_being_processed;

    reg [7:0] debug_counter_writeaddr;

    // Frame buffer BRAM
    reg [PIXEL_WIDTH-1:0] frame_buffer_din;
    wire [PIXEL_WIDTH-1:0] frame_buffer_dout;
    reg frame_buffer_we;
    reg [FRAME_ADDR_WIDTH-1:0] frame_buffer_addr;

    // 3x3 neighborhood BRAM
    reg [PIXEL_WIDTH-1:0] neighborhood_bram [0:8];
    wire [PIXEL_WIDTH-1:0] processed_pixel;
    wire process_done;

    // Debugging signals
    reg [31:0] debug_counter;
    reg [31:0] capture_counter;
    reg [31:0] empty_fifo_counter;
    reg [31:0] data_received_counter;
    reg [31:0] last_write_addr;
    reg write_addr_changed;
    wire [7:0] upsample_debug_leds;

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
        .debug_leds(upsample_debug_leds)
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
            debug_counter_writeaddr <= 0;
            process_addr <= 0;
            processing_done <= 0;
            write_fifo <= 0;
            pixel_data <= 0;
            frame_buffer_we <= 0;
            frame_buffer_addr <= 0;
            frame_buffer_din <= 0;
            frame_capture_complete <= 0;
            frame_being_processed <= 0;
            debug_counter <= 0;
            empty_fifo_counter <= 0;
            led_s <= 8'b0;
            capture_counter <= 0;
            data_received_counter <= 0;
            last_write_addr <= 0;
            write_addr_changed <= 0;
        end else begin
            state <= next_state;
            write_addr <= next_write_addr;
            process_addr <= next_process_addr;
            processing_done <= next_processing_done;
            write_fifo <= next_write_fifo;
            pixel_data <= next_pixel_data;
            frame_capture_complete <= next_frame_capture_complete;
            frame_being_processed <= next_frame_being_processed;

            debug_counter <= debug_counter + 1;

            // Update empty_fifo_counter
            if (state == CAPTURE) begin
                capture_counter <= capture_counter + 1;
                if (data_count_r_sobel > 0) begin
                    data_received_counter <= data_received_counter + 1;
                    empty_fifo_counter <= 0;
                end else begin
                    empty_fifo_counter <= empty_fifo_counter + 1;
                end
            end

            // Check if write_addr has changed
            if (write_addr != last_write_addr) begin
                write_addr_changed <= 1;
                last_write_addr <= write_addr;
            end else begin
                write_addr_changed <= 0;
            end


            // LED indicators
            led_s[0] <= (empty_fifo_counter > 1000000);  // FIFO empty for too long
            led_s[1] <= write_addr_changed;           // write_addr is changing
            led_s[2] <= (write_addr > 100);           // write_addr exceeded 100
            led_s[3] <= (data_received_counter > 0);  // Data being received
            led_s[4] <= (state == CAPTURE);           // In CAPTURE state
            led_s[5] <= frame_capture_complete;       // Frame capture complete
            led_s[6] <= (data_count_r_sobel > 0);     // Data available in input FIFO
            led_s[7] <= (debug_counter[24]);          // Blink every ~0.16 seconds at 100MHz
            
            // case (state)
            //     IDLE: led_s[6] <= 0;
            //     CAPTURE: led_s[6] <= 1;
            //     default: led_s[6] <= led_s[6];
            // endcase

            // // LED[0] now indicates if the input FIFO has been empty for too long during capture
            // led_s[0] <= (empty_fifo_counter > 1000);
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
        next_frame_being_processed = frame_being_processed;
        rd_en = 0;
        rd_fifo_cam = 0;
        frame_buffer_we = 0;
        frame_buffer_addr = write_addr;
        frame_buffer_din = din;

        case (state)
            IDLE: begin
                if (data_count_r_sobel > 0 && !frame_being_processed) begin
                    next_state = CAPTURE;
                    next_write_addr = 0;
                    next_frame_capture_complete = 0;
                    next_frame_being_processed = 1;
                end
            end

            CAPTURE: begin
                if (data_count_r_sobel > 0) begin
                    rd_en = 1;
                    rd_fifo_cam = 1;
                    frame_buffer_we = 1;
                    next_write_addr = write_addr + 1;
                    
                    if (write_addr >= FRAME_SIZE - 1) begin
                        next_frame_capture_complete = 1;
                        next_state = PROCESS;
                        next_process_addr = 0;
                    end
                end

                // Stay in CAPTURE state even if FIFO is temporarily empty
                if (empty_fifo_counter > 1000000) begin // Timeout after long period of empty FIFO
                    next_state = IDLE;
                    next_frame_being_processed = 0;
                end
            end

            PROCESS: begin
                neighborhood_bram[0] = (process_addr >= WIDTH + 1) ? frame_buffer_dout : frame_buffer_dout;
                neighborhood_bram[1] = (process_addr >= WIDTH) ? frame_buffer_dout : frame_buffer_dout;
                neighborhood_bram[2] = (process_addr >= WIDTH - 1) ? frame_buffer_dout : frame_buffer_dout;
                neighborhood_bram[3] = (process_addr % WIDTH != 0) ? frame_buffer_dout : frame_buffer_dout;
                neighborhood_bram[4] = frame_buffer_dout;
                neighborhood_bram[5] = (process_addr % WIDTH != WIDTH - 1) ? frame_buffer_dout : frame_buffer_dout;
                neighborhood_bram[6] = (process_addr < WIDTH * (HEIGHT - 1)) ? frame_buffer_dout : frame_buffer_dout;
                neighborhood_bram[7] = (process_addr < WIDTH * (HEIGHT - 1) + 1) ? frame_buffer_dout : frame_buffer_dout;
                neighborhood_bram[8] = (process_addr < WIDTH * HEIGHT - 1) ? frame_buffer_dout : frame_buffer_dout;
                
                next_state = WAIT_PROCESS;
            end

            WAIT_PROCESS: begin
                if (process_done) begin
                    next_pixel_data = processed_pixel;
                    next_write_fifo = 1;
                    next_process_addr = process_addr + 1;
                    if (process_addr >= FRAME_SIZE - 1) begin
                        next_processing_done = 1;
                        next_state = OUTPUT;
                    end else begin
                        next_state = PROCESS;
                    end
                end
            end

            OUTPUT: begin
                next_write_fifo = 0;
                if (data_count_r == 0) begin
                    next_state = IDLE;
                    next_processing_done = 0;
                    next_frame_being_processed = 0;
                end

                if (data_count_r_sobel > 0) begin
                    rd_en = 1;
                    rd_fifo_cam = 1;
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