module rom #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 16,
    parameter INIT_FILE = "weights.mif"
)(
    input wire [ADDR_WIDTH-1:0] addr,
    output reg [DATA_WIDTH-1:0] q,
    input wire clk
);

    // Declare the ROM variable
    reg [DATA_WIDTH-1:0] rom[0:(1<<ADDR_WIDTH)-1];

    // Initialize the ROM from a memory initialization file
    initial begin
        $readmemh(INIT_FILE, rom);
    end

    // Output the value at the given address
    always @(posedge clk) begin
        q <= rom[addr];
    end
endmodule

