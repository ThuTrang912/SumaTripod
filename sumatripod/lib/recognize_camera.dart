import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'identified_object.dart';
import 'dart:ui' show lerpDouble;
import 'dart:typed_data';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'main.dart';
import 'video_album.dart';
import 'record_camera.dart';
import 'settings_screen.dart';
import 'identified_objects_history.dart'; // Import the new screen
import 'package:image/image.dart' as img;

class RecognizeCamera extends StatefulWidget {
  final CameraDescription camera;
  final bool isFlashOn;

  const RecognizeCamera({
    super.key,
    required this.camera,
    required this.isFlashOn,
  });

  @override
  _RecognizeCameraState createState() => _RecognizeCameraState();
}

class _RecognizeCameraState extends State<RecognizeCamera> {
  late CameraController _controller;
  bool _isCameraInitialized = false;
  bool _isFlashOn = false;
  late List<CameraDescription> _cameras;
  late CameraDescription _currentCamera;
  List<String> _identifiedObjects = [];

  @override
  void initState() {
    super.initState();
    _isFlashOn = widget.isFlashOn;
    _initializeCameras();
  }

  Future<void> _initializeCameras() async {
    _cameras = await availableCameras();
    _currentCamera = widget.camera;
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    await _requestCameraPermission();
    await _requestStoragePermission();
    _initializeCamera(_currentCamera);
  }

  Future<void> _requestCameraPermission() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      var result = await Permission.camera.request();
      if (!result.isGranted) {
        print('Camera permission denied');
        return;
      }
    }
  }

  Future<void> _requestStoragePermission() async {
    if (Platform.isAndroid &&
        await Permission.manageExternalStorage.isGranted) {
      print('Manage external storage permission granted');
    } else {
      var status = await Permission.storage.request();
      if (status.isGranted) {
        print('Storage permission granted');
      } else {
        print('Storage permission denied');
      }
    }
  }

  Future<void> _initializeCamera(CameraDescription cameraDescription) async {
    _controller = CameraController(cameraDescription, ResolutionPreset.medium);
    try {
      await _controller.initialize();
      print('Camera initialized');
    } catch (e) {
      print('Error initializing camera: $e');
    }
    if (!mounted) return;

    setState(() {
      _isCameraInitialized = true;
    });
  }

  void _switchCamera() {
    final newCamera = _cameras.firstWhere(
      (camera) => camera.lensDirection != _currentCamera.lensDirection,
    );
    setState(() {
      _currentCamera = newCamera;
      _isCameraInitialized = false;
    });
    _initializeCamera(newCamera);
  }

  void _toggleFlash() async {
    if (_isFlashOn) {
      await _controller.setFlashMode(FlashMode.off);
    } else {
      await _controller.setFlashMode(FlashMode.torch);
    }
    setState(() {
      _isFlashOn = !_isFlashOn;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _takePicture() async {
    if (!_isCameraInitialized) {
      print('Camera not initialized yet');
      return;
    }

    try {
      final XFile picture = await _controller.takePicture();

      final File imageFile = File(picture.path);

      // Flip the image if using the front camera
      if (_currentCamera.lensDirection == CameraLensDirection.front) {
        final bytes = await imageFile.readAsBytes();
        img.Image originalImage = img.decodeImage(Uint8List.fromList(bytes))!;
        img.Image flippedImage = img.flipHorizontal(originalImage);
        await imageFile.writeAsBytes(img.encodeJpg(flippedImage));
      }

      _identifiedObjects.add(picture.path);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => IdentifiedObject(
            imagePath: picture.path,
            camera: _currentCamera,
          ),
        ),
      );
    } catch (e) {
      print("Error taking picture: $e");
    }
  }

  void _pickImageFromGallery() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => IdentifiedObject(
            imagePath: image.path,
            camera: _currentCamera,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Color(0xFF333333),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => GetStartedScreen()),
              (Route<dynamic> route) => false,
            );
          },
        ),
        title: Text(''),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: Colors.white),
            onSelected: (String result) {
              if (result == 'Settings') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => SettingsScreen()),
                );
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'Settings',
                child: Text('Settings'),
              ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(40),
          child: CustomFunctionBarRecognize(
            onSwitchCamera: _switchCamera,
            onToggleFlash: _toggleFlash,
            isFlashOn: _isFlashOn,
            identifiedObjects: _identifiedObjects,
          ),
        ),
      ),
      body: Stack(
        children: [
          if (_isCameraInitialized)
            Positioned.fill(
              child: CameraPreview(_controller),
            ),
          if (!_isCameraInitialized) Center(child: CircularProgressIndicator()),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: CustomPaint(
              size: Size(MediaQuery.of(context).size.width, 60),
              painter: BottomBarPainter(),
              child: SizedBox(
                height: 60,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    GestureDetector(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => VideoAlbum(refresh: true),
                          ),
                        );
                        // No need to reinitialize camera or reset detection state
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.rectangle,
                          borderRadius: BorderRadius.circular(5),
                          image: DecorationImage(
                            image: AssetImage('assets/gallery.png'),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 40),
                    IconButton(
                      icon: Icon(Icons.photo_library_outlined),
                      color: Colors.white,
                      onPressed: _pickImageFromGallery,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 22,
            left: MediaQuery.of(context).size.width / 2 - 35,
            child: Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.orange,
              ),
              child: IconButton(
                icon: Icon(Icons.camera_alt_outlined),
                color: Colors.black,
                iconSize: 35,
                onPressed: _takePicture,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BottomBarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Color(0xFF333333);

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * 0.5, 0)
      ..arcToPoint(
        Offset(size.width * 0.5, 0),
        radius: Radius.circular(80),
        clockwise: false,
      )
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return false;
  }
}

class CustomFunctionBarRecognize extends StatelessWidget {
  final VoidCallback onSwitchCamera;
  final VoidCallback onToggleFlash;
  final bool isFlashOn;
  final List<String> identifiedObjects;

  const CustomFunctionBarRecognize({
    required this.onSwitchCamera,
    required this.onToggleFlash,
    required this.isFlashOn,
    required this.identifiedObjects,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Color(0xFF333333),
      child: Column(
        children: [
          SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                icon: Icon(Icons.history, color: Colors.white),
                onPressed: () {
                  // Add functionality for the history icon
                },
              ),
              IconButton(
                icon: Icon(
                  isFlashOn ? Icons.flash_on : Icons.flash_off,
                  color: Colors.white,
                ),
                onPressed: onToggleFlash,
              ),
              IconButton(
                icon: Icon(Icons.flip_camera_ios_outlined, color: Colors.white),
                onPressed: onSwitchCamera,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
