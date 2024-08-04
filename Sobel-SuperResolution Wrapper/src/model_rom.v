module model_rom(
    input clk,
    input [ADDR_WIDTH-1:0] addr,
    output reg [DATA_WIDTH*BATCH_SIZE-1:0] data_out
);
    parameter DATA_WIDTH = 8;
    parameter ADDR_WIDTH = 16;
    parameter BATCH_SIZE = 8;
    parameter ROM_SIZE = 65536; // Adjust based on actual size needed

    reg [DATA_WIDTH-1:0] rom[0:ROM_SIZE-1];

    initial begin
        $readmemh("smallmodelweights.mem", rom);
    end

    always @(posedge clk) begin
        integer i;
        for (i = 0; i < BATCH_SIZE; i = i + 1) begin
            data_out[DATA_WIDTH*(i+1)-1:DATA_WIDTH*i] <= rom[addr + i];
        end
    end
endmodule

