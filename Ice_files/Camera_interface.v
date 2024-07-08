module camera_interface(
    input wire clk,
    input wire clk_100,
    input wire rst_n,
    input wire[3:0] key, // key[1:0] for brightness control, key[3:2] for contrast control
    // sobel
    input wire rd_en_sobel,
    output wire[16:0] dout_sobel,
    output wire[9:0] data_count_r_sobel,
    // camera fifo IO
    input wire rd_en,
    output wire[10:0] data_count_r,
    output wire[16:0] dout,
    // camera pinouts
    input wire cmos_pclk,
    input wire cmos_href,
    input wire cmos_vsync,
    input wire[7:0] cmos_db,
    inout cmos_sda,
    inout cmos_scl, // i2c comm wires
    output wire cmos_rst_n,
    output wire cmos_pwdn,
    output wire cmos_xclk,
    // Debugging
    output wire[7:0] led
);
    // FSM state declarations
    localparam idle = 0,
        start_sccb = 1,
        write_address = 2,
        write_data = 3,
        digest_loop = 4,
        delay = 5,
        vsync_fedge = 6,
        byte1 = 7,
        byte2 = 8,
        fifo_write = 9,
        stopping = 10;

    localparam wait_init = 0,
        sccb_idle = 1,
        sccb_address = 2,
        sccb_data = 3,
        sccb_stop = 4;

    localparam MSG_INDEX = 77; // number of the last index to be digested by SCCB

    reg[3:0] state_q = 0, state_d;
    reg[2:0] sccb_state_q = 0, sccb_state_d;
    reg[7:0] addr_q, addr_d;
    reg[7:0] data_q, data_d;
    reg[7:0] brightness_q, brightness_d;
    reg[7:0] contrast_q, contrast_d;
    reg start, stop;
    reg[7:0] wr_data;
    reg[7:0] led_q = 0, led_d; 
    reg[27:0] delay_q = 0, delay_d;
    reg start_delay_q = 0, start_delay_d;
    reg delay_finish;
    reg[15:0] message[250:0];
    reg[7:0] message_index_q = 0, message_index_d;
    reg[16:0] pixel_q, pixel_d;
    reg wr_en;

    wire rd_tick;
    wire[1:0] ack;
    wire[7:0] rd_data;
    wire[3:0] state;
    wire full;
    wire key0_tick, key1_tick, key2_tick, key3_tick;
    wire empty_sobel;

    // Buffer for all inputs coming from the camera
    reg pclk_1, pclk_2, href_1, href_2, vsync_1, vsync_2;

    initial begin // Collection of all addresses and values to be written in the camera
        // {address, data}
        message[0] = 16'h12_80; // Reset all register to default values
        message[1] = 16'h12_04; // Set output format to RGB
        message[2] = 16'h15_20; // PCLK will not toggle during horizontal blank
        message[3] = 16'h40_d0; // RGB565

        // Values scalped from https://github.com/jonlwowski012/OV7670_NEXYS4_Verilog/blob/master/ov7670_registers_verilog.v
        message[4] = 16'h12_04; // COM7, set RGB color output
        message[5] = 16'h11_80; // CLKRC internal PLL matches input clock
        message[6] = 16'h0C_00; // COM3, default settings
        message[7] = 16'h3E_00; // COM14, no scaling, normal pclock
        message[8] = 16'h04_00; // COM1, disable CCIR656
        message[9] = 16'h40_d0; // COM15, RGB565, full output range
        message[10] = 16'h3a_04; // TSLB set correct output data sequence (magic)
        message[11] = 16'h14_18; // COM9 MAX AGC value x4 0001_1000
        message[12] = 16'h4F_B3; // MTX1 all of these are magical matrix coefficients
        message[13] = 16'h50_B3; // MTX2
        message[14] = 16'h51_00; // MTX3
        message[15] = 16'h52_3d; // MTX4
        message[16] = 16'h53_A7; // MTX5
        message[17] = 16'h54_E4; // MTX6
        message[18] = 16'h58_9E; // MTXS
        message[19] = 16'h3D_C0; // COM13 sets gamma enable, does not preserve reserved bits, may be wrong?
        message[20] = 16'h17_14; // HSTART start high 8 bits
        message[21] = 16'h18_02; // HSTOP stop high 8 bits // these kill the odd colored line
        message[22] = 16'h32_80; // HREF edge offset
        message[23] = 16'h19_03; // VSTART start high 8 bits
        message[24] = 16'h1A_7B; // VSTOP stop high 8 bits
        message[25] = 16'h03_0A; // VREF vsync edge offset
        message[26] = 16'h0F_41; // COM6 reset timings
        message[27] = 16'h1E_00; // MVFP disable mirror / flip // might have magic value of 03
        message[28] = 16'h33_0B; // CHLF // magic value from the internet
        message[29] = 16'h3C_78; // COM12 no HREF when VSYNC low
        message[30] = 16'h69_00; // GFIX fix gain control
        message[31] = 16'h74_00; // REG74 Digital gain control
        message[32] = 16'hB0_84; // RSVD magic value from the internet *required* for good color
        message[33] = 16'hB1_0c; // ABLC1
        message[34] = 16'hB2_0e; // RSVD more magic internet values
        message[35] = 16'hB3_80; // THL_ST
        // Begin mystery scaling numbers
        message[36] = 16'h70_3a;
        message[37] = 16'h71_35;
        message[38] = 16'h72_11;
        message[39] = 16'h73_f0;
        message[40] = 16'ha2_02;
        // Gamma curve values
        message[41] = 16'h7a_20;
        message[42] = 16'h7b_10;
        message[43] = 16'h7c_1e;
        message[44] = 16'h7d_35;
        message[45] = 16'h7e_5a;
        message[46] = 16'h7f_69;
        message[47] = 16'h80_76;
        message[
endmodule
