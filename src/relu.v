
module relu(
    input wire [23:0] pixel_in,
    output wire [23:0] pixel_out
);
    assign pixel_out[23:16] = (pixel_in[23:16] > 8'd0) ? pixel_in[23:16] : 8'd0;
    assign pixel_out[15:8]  = (pixel_in[15:8]  > 8'd0) ? pixel_in[15:8]  : 8'd0;
    assign pixel_out[7:0]   = (pixel_in[7:0]   > 8'd0) ? pixel_in[7:0]   : 8'd0;
endmodule   