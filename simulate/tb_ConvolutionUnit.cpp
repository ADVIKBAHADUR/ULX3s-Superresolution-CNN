#include <verilated.h>
#include "V2dConv.h"
#include <iostream>

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    V2dConv* top = new V2dConv;

    // Initialize inputs
    top->clk = 0;
    top->rst_n = 0;

    // Apply some input values
    for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 3; j++) {
            for (int k = 0; k < 3; k++) {
                top->input_data[i][j][k] = (i * 3 + j * 3 + k + 1);
            }
        }
    }

    // Simulation time
    vluint64_t sim_time = 0;

    // Simulation loop
    while (!Verilated::gotFinish()) {
        // Toggle clock
        top->clk = !top->clk;

        // Apply reset for the first few cycles
        if (sim_time > 20) {
            top->rst_n = 1;
        }

        // Evaluate model
        top->eval();

        // Print output values at some point
        if (sim_time == 1000) {
            std::cout << "Output data:" << std::endl;
            for (int i = 0; i < 3; i++) {
                for (int j = 0; j < 3; j++) {
                    for (int k = 0; k < 3; k++) {
                        std::cout << "output_data[" << i << "][" << j << "][" << k << "] = " << top->output_data[i][j][k] << std::endl;
                    }
                }
            }
        }

        // End simulation after some time
        if (sim_time > 2000) {
            break;
        }

        // Advance simulation time
        sim_time++;
    }

    // Cleanup
    top->final();
    delete top;
    return 0;
}
