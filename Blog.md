This markdown file shows the entire journey of development of this system. From errors, to bugs, to blockers, to successes

First I have put the Efficient Teacher Student Distillation model repo as a submodule in this repo. A new branch has been created for the FPGA system in the Efficient Teacher Student Model. 

Now my task is to figure out convert this Pytorch trained model to a bitstream i can put into the ULX3s

For this to be possible. I first need to convert the pytorch model into a ONNX model. 

To convert to ONNX, pytorch has a built in export function. I need to figure out how to use. 

First I asked GPT. It led me the route of running a quantisation followed by exporting to ONNX. 

The code looked like this 


```python
lr_dir = '/content/drive/MyDrive/SuperResolution/SuperResolution/ESRGAN/train'

class SuperResolutionDataset(Dataset):
    def __init__(self, root_dir, transform=None, target_size=(64, 64)):
        self.root_dir = root_dir
        self.lr_images = []
        for subdir, _, files in os.walk(root_dir):
            for file in files:
                if file.endswith(('png', 'jpg', 'jpeg', 'bmp', 'tiff')) and not file.startswith('.'):
                    self.lr_images.append(os.path.join(subdir, file))
        self.transform = transform
        self.target_size = target_size

    def __len__(self):
        return len(self.lr_images)

    def __getitem__(self, idx):
        lr_image_path = self.lr_images[idx]
        lr_image = Image.open(lr_image_path).convert('RGB')
        lr_image = lr_image.resize(self.target_size, Image.BICUBIC)
        lr_image = self.anti_aliasing_preprocessing(lr_image)
        if self.transform:
            lr_image = self.transform(lr_image)
        return lr_image

    def anti_aliasing_preprocessing(self, image):
        # Apply Gaussian Blur to reduce aliasing artifacts
        image = image.filter(ImageFilter.GaussianBlur(radius=1))
        return image

class StudentModel(nn.Module):
    def __init__(self, scale_factor=4):
        super(StudentModel, self).__init__()
        self.upsample = nn.Sequential(
            nn.Conv2d(3, 3 * (scale_factor ** 2), kernel_size=3, stride=1, padding=1),
            nn.PixelShuffle(scale_factor)
        )
        self.conv1 = nn.Conv2d(3, 64, kernel_size=3, stride=1, padding=1)
        self.conv2 = nn.Conv2d(64, 64, kernel_size=3, stride=1, padding=1)
        self.conv3 = nn.Conv2d(64, 64, kernel_size=3, stride=1, padding=1)
        self.conv4 = nn.Conv2d(64, 64, kernel_size=3, stride=1, padding=1)
        self.conv5 = nn.Conv2d(64, 3, kernel_size=3, stride=1, padding=1)

        self.relu = nn.ReLU(inplace=True)

    def forward(self, x):
        x = self.upsample(x)
        x = self.conv1(x)
        x = self.conv2(x)
        x = self.conv3(x)
        x = self.conv4(x)
        x = self.conv5(x)
        x = self.relu(x)
        return x

model = StudentModel()
model.eval()

# Specify the backend for quantization (QuantizedCPU)
torch.backends.quantized.engine = 'qnnpack'

model.qconfig = quantization.get_default_qconfig('qnnpack')
quantization.prepare(model, inplace=True)

transform = transforms.Compose([
    transforms.ToTensor(),
])

calibration_dataset = SuperResolutionDataset(root_dir=lr_dir, transform=transform, target_size=(64, 64))

# Sample 100 random indices from the dataset
random_indices = random.sample(range(len(calibration_dataset)), 100)
reduced_calibration_dataset = Subset(calibration_dataset, random_indices)

calibration_data = DataLoader(reduced_calibration_dataset, batch_size=1, shuffle=False)

# Calibration with representative data
with torch.no_grad():
    for input in calibration_data:
        model(input)

quantization.convert(model, inplace=True)

# Define a dummy input tensor with the determined size
sample_image_path = '/content/drive/MyDrive/SuperResolution/SuperResolution/ESRGAN/train/0024000/0023975x4.png'
sample_image = Image.open(sample_image_path)
input_size = sample_image.size  # This will give you (width, height)

dummy_input = torch.randn(1, 3, input_size[1], input_size[0])  # (batch_size, channels, height, width)

# Specify the path where you want to save the ONNX model
onnx_model_path = "quantized_model.onnx"

# Export the model to ONNX format
torch.onnx.export(
    model,                     # model being run
    dummy_input,               # model input (or a tuple for multiple inputs)
    onnx_model_path,           # where to save the model (can be a file or file-like object)
    export_params=True,        # store the trained parameter weights inside the model file
    opset_version=12,          # the ONNX version to export the model to
    do_constant_folding=True,  # whether to execute constant folding for optimization
    input_names=['input'],     # the model's input names
    output_names=['output'],   # the model's output names
    dynamic_axes={'input': {0: 'batch_size'}, 'output': {0: 'batch_size'}}  # variable length axes
)

print(f"ONNX model has been saved to {onnx_model_path}")

```

I keep getting some weird error somehow saying:

```console
NotImplementedError: Could not run 'quantized::conv2d.new' with arguments from the 'CPU' backend. This could be because the operator doesn't exist for this backend, or was omitted during the selective/custom build process (if using custom build). If you are a Facebook employee using PyTorch on mobile, please visit https://fburl.com/ptmfixes for possible resolutions. 'quantized::conv2d.new' is only available for these backends: [Meta, QuantizedCPU, QuantizedCUDA, BackendSelect, Python, FuncTorchDynamicLayerBackMode, Functionalize, Named, Conjugate, Negative, ZeroTensor, ADInplaceOrView, AutogradOther, AutogradCPU, AutogradCUDA, AutogradXLA, AutogradMPS, AutogradXPU, AutogradHPU, AutogradLazy, AutogradMeta, Tracer, AutocastCPU, AutocastCUDA, FuncTorchBatched, BatchedNestedTensor, FuncTorchVmapMode, Batched, VmapMode, FuncTorchGradWrapper, PythonTLSSnapshot, FuncTorchDynamicLayerFrontMode, PreDispatch, PythonDispatcher].

Meta: registered at ../aten/src/ATen/core/MetaFallbackKernel.cpp:23 [backend fallback]
QuantizedCPU: registered at ../aten/src/ATen/native/quantized/cpu/qconv.cpp:1928 [kernel]
```
Hence I have decided to go look into the actual documentation of pytorch and do it myself. This error is pretty unsolveable for me at the moment.

I am using this tutorial:
```html
https://pytorch.org/tutorials/beginner/onnx/export_simple_model_to_onnx_tutorial.html
```

Code for this is in the *pytorch_to_onnx.ipynb* file

Suprise Suprise! It actually worked first try!
It is not doing any quantisation as GPT was trying to do, but I will have a look at it later to figure it out. 

# Figuring out how to make the camera work. 
This repo here 
``` html
https://github.com/AngeloJacobo/ULX3S_FPGA_Sobel_Edge_Detection_OV7670 
```
Runs a Sobel model to return the edges of an image taken directly from the OV7670 Camera and returns it to the HDMI port. Fully open source, really good.

But I am finding it hard to figure out how to make the camera work. 
Since this is also a learning project I want to understand how the Camera is working, what are the actual inputs into our model on the hardware level. 

So I found this hackster article:
```html
https://www.hackster.io/dhq/fpga-camera-system-14d6ea
```
## Some Notes 
1) **HSYNC** is a binary key returned when one row of pixels of one frame is completed transmission. 
2) **HREF** remains HIGH when actual / relevant horizontal row data is being transmitted. Usually the HSYNC pulse is around the HREF active period. 
3) **VYSNC** is returned when one complete frame is transmitted. 
![alt text](<Camera_Basic_Signals.png>)

Hence we get pixed by pixel data, from left to right, top to bottom. 
If i consider 640x480p wide image, and storing the frame at each point, we will be a challenge?

<iframe frameborder="0" style="width:100%;height:328px;" src="https://viewer.diagrams.net/?tags=%7B%7D&highlight=0000ff&edit=_blank&layers=1&nav=1&title=#RzVjbbqMwEP0aHrcyECB5bJvepO2qKlJ3%2B%2BgEJ1gFjIxJQr9%2Bx8FcHNP0kvTyFGY8Y3xmjg92LPc83VxxnMe3LCKJ5aBoY7lTy3Fs5I3hR3qq2hMEbu1YchqpoM4R0mfSZCpvSSNSaIGCsUTQXHfOWZaRudB8mHO21sMWLNHfmuMlMRzhHCem9y%2BNRFx7x07Q%2Ba8JXcbNm21%2FUo%2BkuAlWSIoYR2zdc7kXlnvOGRP1U7o5J4ksXlOXOu%2FyhdF2YZxk4i0JozphhZNSYVPrElUDlkSAXZkZy%2BDnLBZpApYNj3W4jHlxBcpVsJLPVZR6i8B8SVSU26IH2hCWEsErCOEkwYKu9Nmx6t%2ByjesgwoNCOYzYMRBfwRIcdEc3W5beZAvGoU%2BUZUYpOCuziEQK%2BjqmgoQ53oJaA9OHKrMiXJDN%2FtqYqFWCr1iitslEmeuOc%2FZI%2BeIe3zx0eJk8o0x0AfZ1%2BPgHctHWhZBRof1kAdi8%2Btc3HsFAJ15jTiVw1FqVsj5GMtckmXMgybapp5zjqheQM5qJojfznXR0XXQCvY3OyNP35Cvxtu3tdK5eQdfHFsqbWuu%2F2lr7nX09Wn%2BCY%2FTHKOgIDTegnaJegsra2SPvq61r1DYUjJOevkyxwDIhk9BJmt%2Bz9QPmFM%2BgtrtVf0VhdDk6gt7sElURTxMcZ0Bw%2FCMIzvhHa0nwQ7RkNPlcbZgY%2FBW8NIkpy%2Fcbz4DQWk9wQpcZPM%2BhlISDQ7KRwrnpVA2kNIrkHGecFPR5y%2Fm6Kwo3TO6dWd50H53VoU4lW%2B1Rqt%2FB8V6a%2F0In%2FqTZqpU2%2BUeVpglhi0VBDhUR2x5W6IevVugB1ttouLRHP6cFppLilRRSEMwdGb3kOIURH6dSILNZkbeIv%2FHwNnK%2FUU1t80P0JYxpbmgaZQ5VyjeDRgbo%2B1ISJCxzkCOgDilYUg4e7b%2F6U%2Bv738kO8xIUxtttdZPKq6%2BDZnj%2BJNvI5MFwenvz4%2Brlep9XLzC7G3it393%2FGO7Ffw%3D%3D"></iframe>

Full VGA -- 640 x 480
Half VGA -- 320 x 480
4x Half VGA -- 1920 x 1280

