module weight_loader #(
    parameter ADDR_WIDTH = 20,
    parameter DATA_WIDTH = 8,
    parameter MEM_SIZE = 3048  // Adjust this based on your model's total weights and biases
)(
    input wire clk,
    input wire rst_n,
    input wire load_weights,
    input wire [ADDR_WIDTH-1:0] addr,
    output reg [DATA_WIDTH-1:0] weight_out,
    output reg [7:0] debug_leds
);
    reg [DATA_WIDTH-1:0] weight_mem [0:MEM_SIZE-1];
    reg [DATA_WIDTH-1:0] prev_weight;
    reg [ADDR_WIDTH-1:0] max_addr_accessed;
    reg weights_loaded;
    reg [15:0] non_zero_count;
    reg [15:0] varying_count;
    always @(posedge clk or negedge rst_n) begin
        if (load_weights && rst_n) begin
            $display("Time: %0t | Address: %0d | Data: %0h", $time, addr, weight_mem[addr]);
        end
    end

    
    initial begin
        $readmemh("smallmodelweights.mem", weight_mem);
        weights_loaded = 0;
        max_addr_accessed = 0;
        non_zero_count = 0;
        varying_count = 0;
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weight_out <= 0;
            prev_weight <= 0;
            weights_loaded <= 0;
            max_addr_accessed <= 0;
            non_zero_count <= 0;
            varying_count <= 0;
            debug_leds <= 8'b0;
        end else if (load_weights) begin
            weight_out <= weight_mem[addr];
            
            // Update max address accessed
            if (addr > max_addr_accessed) begin
                max_addr_accessed <= addr;
            end
            
            // Check if weight is non-zero
            if (weight_mem[addr] != 0) begin
                non_zero_count <= non_zero_count + 1;
            end
            
            // Check if weight is different from previous
            if (weight_mem[addr] != prev_weight) begin
                varying_count <= varying_count + 1;
            end
            
            prev_weight <= weight_mem[addr];
            weights_loaded <= 1;
            
            // Update debug LEDs
            debug_leds[0] <= weights_loaded;                          // Indicate if weights have been loaded
            debug_leds[1] <= (weight_mem[addr] != 0);                 // Current weight is non-zero
            debug_leds[2] <= (weight_mem[addr] != prev_weight);       // Current weight is different from previous
            debug_leds[3] <= (addr == max_addr_accessed);             // Reached the highest address so far
            debug_leds[4] <= (non_zero_count > 0);                    // At least one non-zero weight encountered
            debug_leds[5] <= (varying_count > 0);                     // At least one varying weight encountered
            debug_leds[6] <= (addr == MEM_SIZE - 1);                  // Reached the last address
            debug_leds[7] <= load_weights;                            // Load weights signal is active
        end
    end
endmodule

