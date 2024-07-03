This markdown file shows the entire journey of development of this system. From errors, to bugs, to blockers, to successes

First I have put the Efficient Teacher Student Distillation model repo as a submodule in this repo. A new branch has been created for the FPGA system in the Efficient Teacher Student Model. 

Now my task is to figure out convert this Pytorch trained model to a bitstream i can put into the ULX3s

For this to be possible. I first need to convert the pytorch model into a ONNX model. 

To convert to ONNX, pytorch has a built in export function. I need to figure out how to use. 


