- Created by: Advik Bahadur
- Project: Implementing a Superresolution model onto a ULX3s FPGA Board developed by Radiona.org

# FPGA-based Super-Resolution Image Processing

## Project Overview

This project implements a real-time super-resolution image processing system on an FPGA. It takes low-resolution input from a camera, processes it through a custom neural network, and outputs a higher-resolution image. The system is designed to work with the OV7670 camera module and uses SDRAM for frame buffering.

## Key Components

1. Camera Interface (OV7670)
2. SDRAM Controller
3. Super-Resolution Neural Network
4. VGA Output

## Features

- Real-time image capture and processing
- Custom neural network for super-resolution
- SDRAM-based frame buffering
- VGA output for displaying processed images
- Configurable image enhancement (brightness, contrast)

## Hardware Requirements

- FPGA development board (compatible with provided pin assignments)
- OV7670 camera module
- SDRAM module
- VGA display

## Software Requirements

- Verilog synthesis and simulation tools (e.g., Vivado, Quartus)
- Python environment for neural network training (if modifying the model)

## Setup Instructions

1. Clone the repository to your local machine.

2. Connect the hardware components:
   - Attach the OV7670 camera module to the appropriate FPGA pins.
   - Connect the SDRAM module to the designated FPGA pins.
   - Connect a VGA display to the FPGA's VGA output.

3. Open the project in your FPGA development environment.

4. Synthesize the Verilog code and generate the bitstream.

5. Program the FPGA with the generated bitstream.

6. Power on the system and connect the camera module.

## Usage

1. After powering on, the system will initialize the camera and SDRAM.

2. The camera will start capturing images, which will be processed in real-time by the super-resolution neural network.

3. The processed higher-resolution image will be displayed on the connected VGA display.

4. Use the designated keys to adjust brightness and contrast:
   - Key[0]: Increase brightness
   - Key[1]: Decrease brightness
   - Key[2]: Increase contrast
   - Key[3]: Decrease contrast

## Module Descriptions

- `top_module`: The main module that integrates all components.
- `camera_interface`: Handles communication with the OV7670 camera.
- `sdram_interface`: Manages reading and writing to the SDRAM.
- `SuperResolutionSubTop`: Coordinates the super-resolution processing.
- `superresolution`: Implements the neural network for super-resolution.
- `vga_interface`: Manages the VGA output.

## Customization

To modify the neural network architecture or weights:

1. Update the `superresolution` module in the Verilog code.
2. Modify the `smallmodelweights.mem` file with new weight values.
3. Adjust the `WEIGHT_ADDR_WIDTH` and other parameters as needed.

## Troubleshooting

- If the image appears distorted, check the camera configuration and SDRAM timing.
- For VGA sync issues, verify the VGA module parameters match your display.
- LED indicators on the FPGA board can help diagnose various stages of the pipeline.

## Contributing

Contributions to improve the project are welcome. Please submit pull requests or open issues for any bugs or enhancements.

## Acknowledgments

- Radiona.org
- Laidlaw Foundation.
