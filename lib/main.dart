import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'dart:io';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Background Remover',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  File? _image;
  final ImagePicker _picker = ImagePicker();
  late Interpreter _interpreter;

  @override
  void initState() {
    super.initState();
    _loadModel();
    _loadModel();
  }

  Future<void> _loadModel() async {
    _interpreter = await Interpreter.fromAsset('assets/deeplab.tflite');
    _interpreter
        .allocateTensors(); // Ensure tensors are allocated after loading the model
  }

  Future<void> _pickImage() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      _image = File(pickedFile.path);
      final inputImage =
          await _resizeImage(_image!, 257, 257); // Change to 257x257
      _removeBackground(inputImage);
    }
  }

  Future<Uint8List> _resizeImage(File image, int width, int height) async {
    final bytes = await image.readAsBytes();
    final codec = await instantiateImageCodec(bytes,
        targetWidth: width, targetHeight: height);
    final frame = await codec.getNextFrame();
    final resizedImage = await frame.image.toByteData(
        format: ImageByteFormat.rawRgba); // Change to rawRgba for consistency
    print('Expected image length: ${width * width * 4}');
    return resizedImage!.buffer.asUint8List();
  }

  Future<void> _removeBackground(Uint8List image) async {
    _interpreter.allocateTensors();

    final input = imageToByteListFloat32(image, 257, 257)
        .buffer
        .asFloat32List()
        .reshape([1, 257, 257, 3]);

    final output = Float32List(1 * 257 * 257 * 21)
        .buffer
        .asFloat32List()
        .reshape([1, 257, 257, 21]);

    _interpreter.run(input, output);

    // Create RGBA pixel data based on output
    final pixels = List<int>.filled(257 * 257 * 4, 0); // RGBA format
    for (int i = 0; i < 257; i++) {
      for (int j = 0; j < 257; j++) {
        int maxIndex = 0;
        for (int c = 1; c < 21; c++) {
          if (output[0][i][j][c] > output[0][i][j][maxIndex]) {
            maxIndex = c;
          }
        }
        pixels[(i * 257 + j) * 4 + 0] =
            maxIndex * 12; // Arbitrary color mapping
        pixels[(i * 257 + j) * 4 + 1] = maxIndex * 8;
        pixels[(i * 257 + j) * 4 + 2] = maxIndex * 5;
        pixels[(i * 257 + j) * 4 + 3] = 255; // Alpha channel
      }
    }

    // Create an image from the pixel data
    final ui.Image img = await _createImageFromPixels(pixels, 257, 257);

    // Save the image
    final resultBytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final resultImage = File(
        '${Directory.systemTemp.path}/result_${DateTime.now().millisecondsSinceEpoch}.png');
    await resultImage.writeAsBytes(resultBytes!.buffer.asUint8List());

    setState(() {
      _image = resultImage;
    });
  }

  Future<ui.Image> _createImageFromPixels(
      List<int> pixels, int width, int height) async {
    final completer = Completer<ui.Image>();
    final img = ui.decodeImageFromPixels(Uint8List.fromList(pixels), width,
        height, ui.PixelFormat.rgba8888, completer.complete);
    return completer.future;
  }

  Uint8List imageToByteListFloat32(
      Uint8List image, int inputHeight, int inputWidth) {
    var buffer = Float32List(1 * inputHeight * inputWidth * 3).buffer;
    var byteBuffer = buffer.asFloat32List();

    for (int i = 0; i < inputHeight; i++) {
      for (int j = 0; j < inputWidth; j++) {
        // Assuming the image is in RGBA format
        final pixelIndex = (i * inputWidth + j) * 4;
        byteBuffer[(i * inputWidth + j) * 3 + 0] =
            image[pixelIndex + 0] / 255.0; // R
        byteBuffer[(i * inputWidth + j) * 3 + 1] =
            image[pixelIndex + 1] / 255.0; // G
        byteBuffer[(i * inputWidth + j) * 3 + 2] =
            image[pixelIndex + 2] / 255.0; // B
      }
    }
    return byteBuffer.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Background Remover')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _image == null ? Text('No image selected.') : Image.file(_image!),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _pickImage,
              child: Text('Pick Image'),
            ),
          ],
        ),
      ),
    );
  }
}
