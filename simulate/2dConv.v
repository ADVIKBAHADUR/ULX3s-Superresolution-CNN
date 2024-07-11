module Conv2D (
	clk,
	rst_n,
	input_data,
	output_data
);
	input wire clk;
	input wire rst_n;
	input wire [215:0] input_data;
	output reg [431:0] output_data;
	reg signed [5898239:0] Weights;
	reg signed [10239:0] Biases;
	modelReader SuperResolution(
		.clk(clk),
		.rst_n(rst_n),
		.conv_weights(Weights),
		.conv_biases(Biases)
	);
	reg [3:0] state;
	reg [5:0] kernel;
	reg [2:0] conv;
	reg [2:0] depth;
	reg [2:0] i;
	reg [2:0] j;
	reg [1:0] ki;
	reg [1:0] kj;
	reg signed [47:0] sum;
	always @(posedge clk or negedge rst_n)
		if (!rst_n) begin
			state <= 0;
			conv <= 0;
			kernel <= 0;
			depth <= 0;
			i <= 0;
			j <= 0;
			ki <= 0;
			kj <= 0;
			sum <= 0;
			output_data[416+:16] <= 0;
			output_data[400+:16] <= 0;
			output_data[384+:16] <= 0;
			output_data[368+:16] <= 0;
			output_data[352+:16] <= 0;
			output_data[336+:16] <= 0;
			output_data[320+:16] <= 0;
			output_data[304+:16] <= 0;
			output_data[288+:16] <= 0;
			output_data[272+:16] <= 0;
			output_data[256+:16] <= 0;
			output_data[240+:16] <= 0;
			output_data[224+:16] <= 0;
			output_data[208+:16] <= 0;
			output_data[192+:16] <= 0;
			output_data[176+:16] <= 0;
			output_data[160+:16] <= 0;
			output_data[144+:16] <= 0;
			output_data[128+:16] <= 0;
			output_data[112+:16] <= 0;
			output_data[96+:16] <= 0;
			output_data[80+:16] <= 0;
			output_data[64+:16] <= 0;
			output_data[48+:16] <= 0;
			output_data[32+:16] <= 0;
			output_data[16+:16] <= 0;
			output_data[0+:16] <= 0;
		end
		else
			case (state)
				0: begin
					sum <= 0;
					state <= 1;
				end
				1: begin
					sum <= sum + (input_data[(((((2 - i) * 3) + (2 - j)) * 3) + (2 - depth)) * 8+:8] * Weights[32 * ((((((((4 - conv) * 64) + (63 - kernel)) * 64) + (63 - depth)) * 3) + (2 - (((2 - ki) * 3) + (2 - kj)))) * 3)+:96]);
					if (kj == 2) begin
						kj <= 0;
						if (ki == 2) begin
							ki <= 0;
							if (depth == 2) begin
								depth <= 0;
								state <= 2;
							end
							else
								depth <= depth + 1;
						end
						else
							ki <= ki + 1;
					end
					else
						kj <= kj + 1;
				end
				2: begin
					sum <= sum + Biases[(((4 - conv) * 64) + (63 - kernel)) * 32+:32];
					output_data[(((((2 - i) * 3) + (2 - j)) * 3) + (2 - kernel)) * 16+:16] <= sum[15:0];
					state <= 3;
				end
				3:
					if (kernel == 63) begin
						kernel <= 0;
						if (j == 2) begin
							j <= 0;
							if (i == 2) begin
								i <= 0;
								if (conv == 4) begin
									conv <= 0;
									state <= 4;
								end
								else begin
									conv <= conv + 1;
									state <= 0;
								end
							end
							else begin
								i <= i + 1;
								state <= 0;
							end
						end
						else begin
							j <= j + 1;
							state <= 0;
						end
					end
					else begin
						kernel <= kernel + 1;
						state <= 0;
					end
				4:
					;
			endcase
endmodule
