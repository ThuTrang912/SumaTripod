import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'video_album.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:gallery_saver/gallery_saver.dart';
import 'dart:async';
import 'dart:typed_data';

import 'constants.dart';
import 'identified_object.dart';
import 'video_album.dart';
import 'recognize_camera.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:provider/provider.dart';
import 'bluetooth_connection_manager.dart';
import 'settings_screen.dart'; // Add this line to import the BluetoothSettingsScreen

class RecordCamera extends StatefulWidget {
  final CameraDescription camera;
  final String croppedImagePath;
  final Map<String, dynamic> detectedObject;
  final bool isFlashOn;
  final bool isLocationSearching;

  const RecordCamera({
    super.key,
    required this.camera,
    required this.croppedImagePath,
    required this.detectedObject,
    required this.isFlashOn,
    required this.isLocationSearching,
  });

  @override
  _RecordCameraState createState() => _RecordCameraState();
}

class _RecordCameraState extends State<RecordCamera>
    with TickerProviderStateMixin {
  late CameraController _controller;
  bool _isCameraInitialized = false;
  String _currentCroppedImagePath = '';
  bool _hasStoragePermission = false;
  bool _specifiedObjectDetected = false;
  late AnimationController _animationController;
  bool _isRecording = false;
  bool _isPaused = true; // Start in a paused state
  bool _isFlashOn = false; // Initialize flash state
  bool _isLocationSearching = false; // Mặc định là false (location disabled)
  Timer? _timer;
  Timer? _captureTimer;
  Timer? _durationTimer;
  Duration _recordingDuration = Duration.zero;
  List<Map<String, dynamic>> _detections = [];
  List<String> _videoSegments = [];
  List<String> _savedSegments = [];
  late List<CameraDescription> _cameras;
  late CameraDescription _currentCamera;

  @override
  void initState() {
    super.initState();
    _isFlashOn = widget.isFlashOn; // Set the flash state from the widget
    _initializeCameras();
    _currentCroppedImagePath = widget.croppedImagePath;
    _animationController = AnimationController(
      duration: Duration(seconds: 1),
      vsync: this,
    );
    _checkBluetoothConnection(); // Call the Bluetooth connection check here
  }

  Future<void> _checkBluetoothConnection() async {
    final bluetoothManager =
        Provider.of<BluetoothConnectionManager>(context, listen: false);
    bool isConnected = await bluetoothManager.isConnected();
    if (!isConnected) {
      _showBluetoothDialog();
    }
  }

  void _showBluetoothDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Bluetooth Connection'),
          content: Text(
              'Please connect to the Bluetooth device to control the gimbal.'),
          actions: <Widget>[
            TextButton(
              child: Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('Connect'),
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => BluetoothSettingsScreen(),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
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
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      var result = await Permission.storage.request();
      if (!result.isGranted) {
        print('Storage permission denied');
        return;
      }
    }
  }

  Future<void> _initializeCamera(CameraDescription cameraDescription) async {
    _controller = CameraController(cameraDescription, ResolutionPreset.medium);
    try {
      await _controller.initialize();
      print('Camera initialized');
      if (_isFlashOn) {
        await _controller.setFlashMode(FlashMode.torch);
      }
      setState(() {
        _isCameraInitialized = true;
      });
    } catch (e) {
      print('Error initializing camera: $e');
    }
    if (!mounted) return;
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

  void _toggleLocationSearch() async {
    if (_isLocationSearching) {
      setState(() {
        _isLocationSearching = false;
      });
    } else {
      final bluetoothManager =
          Provider.of<BluetoothConnectionManager>(context, listen: false);
      bool isConnected = await bluetoothManager.isConnected();
      if (isConnected) {
        setState(() {
          _isLocationSearching = true;
        });
      } else {
        _showBluetoothDialog();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _timer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  void _toggleRecordVideo() {
    if (_isRecording || _isPaused) {
      _stopVideoRecording();
    } else {
      _startVideoRecording();
    }
  }

  void _startVideoRecording() async {
    if (!_isCameraInitialized) {
      print('Camera not initialized yet');
      return;
    }

    try {
      await _controller.startVideoRecording();
      print('Video recording started');
      setState(() {
        _isRecording = true;
        _recordingDuration = Duration.zero;
      });

      // Immediately pause the recording
      _pauseRecording();

      // Timer to capture frames every 100 milliseconds
      _captureTimer = Timer.periodic(Duration(milliseconds: 100), (timer) {
        _captureFrame();
      });

      // Timer to update recording duration every second
      _durationTimer = Timer.periodic(Duration(seconds: 1), (timer) {
        if (!_isPaused) {
          setState(() {
            _recordingDuration =
                Duration(seconds: _recordingDuration.inSeconds + 1);
          });
        }
      });
    } catch (e) {
      print("Error starting video recording: $e");
    }
  }

  void _stopVideoRecording() async {
    if (!_isCameraInitialized) {
      print('Camera not initialized yet');
      return;
    }

    try {
      if (_isPaused) {
        _isPaused = false;
        await _controller.startVideoRecording();
      }

      XFile video = await _controller.stopVideoRecording();
      print('Video recording stopped: ${video.path}');

      _timer?.cancel();
      setState(() {
        _isRecording = false;
        _detections = []; // Clear detections when recording stops
        _isPaused = false; // Reset the paused state
      });

      // Save the recorded video segment if the specified object was detected or if paused
      if (_specifiedObjectDetected || _isPaused) {
        _savedSegments.add(video.path);
        _specifiedObjectDetected = false; // Reset the flag
      } else {
        print('Specified object not detected, segment not saved');
      }

      // Save video segments directly without merging
      await saveVideoToStorage(video.path);

      // Send stop command to ESP32
      final bluetoothManager =
          Provider.of<BluetoothConnectionManager>(context, listen: false);
      bluetoothManager.sendGimbalCommand('STOP\n');
    } catch (e) {
      print("Error stopping video recording: $e");
    }
  }

  void _captureFrame() async {
    if (!_isCameraInitialized) {
      print('Camera not initialized yet');
      return;
    }

    try {
      final XFile file = await _controller.takePicture();
      final File imageFile = File(file.path);

      // Send the captured image to the Yolov11 server
      final response = await sendImageToYolov11Server(imageFile);

      // Parse the response and update detections
      var responseJson = json.decode(response);
      var detections = responseJson['detections'];
      List<Map<String, dynamic>> objectDetections = [];
      for (var detection in detections) {
        objectDetections.add({
          'name': detection['name'],
          'x': detection['x'],
          'y': detection['y'],
          'width': detection['width'],
          'height': detection['height'],
          'confidence': detection['confidence'],
          'isSpecifiedObject':
              detection['name'] == widget.detectedObject['name'],
        });
      }

      // Find the object with the smallest absolute difference in confidence
      Map<String, dynamic>? closestConfidenceObject;
      double smallestDifference = double.infinity;
      for (var detection in objectDetections) {
        if (detection['isSpecifiedObject']) {
          double difference =
              (detection['confidence'] - widget.detectedObject['confidence'])
                  .abs();
          if (difference < smallestDifference) {
            smallestDifference = difference;
            closestConfidenceObject = detection;
          }
        }
      }

      setState(() {
        _detections = objectDetections;
      });

      // Check if the detected object is present in the response
      if (closestConfidenceObject != null) {
        _specifiedObjectDetected = true;

        // Resume recording if paused
        if (_isPaused) {
          _resumeRecording();
        }

        // Calculate the offset from the center
        double centerX = MediaQuery.of(context).size.width / 2;
        double centerY = MediaQuery.of(context).size.height / 2;
        double appBarHeight = AppBar().preferredSize.height;

        // double objectCenterX =
        //     closestConfidenceObject['x'] + closestConfidenceObject['width'] / 2;
        // double objectCenterY = closestConfidenceObject['y'] +
        //     closestConfidenceObject['height'] / 2 -
        //     appBarHeight;
        double objectCenterX = closestConfidenceObject['x'] +
            closestConfidenceObject['width'] / 2 -
            appBarHeight;
        double objectCenterY = closestConfidenceObject['y'] +
            closestConfidenceObject['height'] / 2;
        double offsetX = objectCenterX - centerX;
        double offsetY = objectCenterY - centerY;

        print('centerX: $centerX, centerY: $centerY');
        print('objectCenterX: $objectCenterX, objectCenterY: $objectCenterY');
        print('offsetX: $offsetX, offsetY: $offsetY');

        // Convert offset to angles
        double angleX = offsetX / MediaQuery.of(context).size.width * 360;
        double angleY = offsetY / MediaQuery.of(context).size.height * 360;

        print('angleX: $angleX, angleY: $angleY');

        // Calculate speed based on the offset
        // double speedX =
        //     (offsetX.abs() / MediaQuery.of(context).size.width) * 1023;
        // double speedY =
        //     (offsetY.abs() / MediaQuery.of(context).size.height) * 1023;

        double speedX = 1023;
        double speedY = 1023;

        // Send commands to ESP32 to adjust the gimbal
        final bluetoothManager =
            Provider.of<BluetoothConnectionManager>(context, listen: false);
        bluetoothManager
            .sendGimbalCommand('X:$angleX,Y:$angleY,SX:$speedX,SY:$speedY\n');
      } else {
        _specifiedObjectDetected = false;

        // Pause recording if the specified object is not detected
        if (!_isPaused) {
          _pauseRecording();
        }

        // Send stop command to ESP32
        final bluetoothManager =
            Provider.of<BluetoothConnectionManager>(context, listen: false);
        bluetoothManager.sendGimbalCommand('STOP\n');
      }
    } catch (e) {
      print("Error capturing frame: $e");
    }
  }

  void _pauseRecording() async {
    setState(() {
      _isPaused = true;
    });
    XFile video = await _controller.stopVideoRecording();
    _videoSegments.add(video.path);
    print('Video recording paused');

    // Send stop command to ESP32
    final bluetoothManager =
        Provider.of<BluetoothConnectionManager>(context, listen: false);
    bluetoothManager.sendGimbalCommand('STOP\n');
  }

  void _resumeRecording() async {
    setState(() {
      _isPaused = false;
    });
    await _controller.startVideoRecording();
    print('Video recording resumed');
  }

  Future<String> sendImageToYolov11Server(File imageFile) async {
    const url = Constants.yoloServerUrl; // Replace with your server URL
    var request = http.MultipartRequest('POST', Uri.parse(url + '/detect'));
    request.files
        .add(await http.MultipartFile.fromPath('image', imageFile.path));

    var response = await request.send();
    if (response.statusCode == 200) {
      var responseData = await response.stream.bytesToString();
      print('Response Data: $responseData'); // Print the response
      return responseData;
    } else {
      throw Exception('Failed to send image to Yolov11 server');
    }
  }

  Future<void> saveVideoToStorage(String videoPath) async {
    final appDir = await getExternalStorageDirectory();
    final savePath = '${appDir!.path}/my_videos/';

    final directory = Directory(savePath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final File file = File(videoPath);
    final String fileName =
        'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final String newPath = savePath + fileName;
    await file.copy(newPath);

    // Save the video to the device's photo album
    await GallerySaver.saveVideo(newPath);

    // Display a message or update the UI after successfully saving the video
    print('Video saved to gallery: $newPath');
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    final twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    final twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Color(0xFF333333),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () async {
            final cameras = await availableCameras();
            final firstCamera = cameras.first;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => RecognizeCamera(
                  camera: firstCamera,
                  isFlashOn: _isFlashOn, // Pass the flash state
                ),
              ),
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
          child: CustomFunctionBarRecord(
            onSwitchCamera: _switchCamera,
            onToggleFlash: _toggleFlash,
            isFlashOn: _isFlashOn, // Set the initial flash state here
            identifiedObjects: _detections
                .map((detection) => detection['name'].toString())
                .toList(), // Add this line
            isLocationSearching: _isLocationSearching,
            onToggleLocationSearch:
                _toggleLocationSearch, // Pass the location searching state
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
          if (_currentCroppedImagePath.isNotEmpty)
            Positioned(
              top: 20,
              right: 20,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  image: DecorationImage(
                    image: FileImage(File(_currentCroppedImagePath)),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          if (_isRecording)
            Positioned(
              top: 20,
              left: 20,
              child: Container(
                padding: EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  _formatDuration(_recordingDuration),
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              ),
            ),
          if (_isRecording)
            for (var detection in _detections)
              Positioned(
                top: detection['y'] - AppBar().preferredSize.height,
                left: detection['x'] - AppBar().preferredSize.height,
                width: detection['width'],
                height: detection['height'],
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: detection ==
                              _detections.firstWhere(
                                (d) =>
                                    d['isSpecifiedObject'] &&
                                    (d['confidence'] -
                                                widget.detectedObject[
                                                    'confidence'])
                                            .abs() ==
                                        _detections
                                            .where(
                                                (d) => d['isSpecifiedObject'])
                                            .map((d) => (d['confidence'] -
                                                    widget.detectedObject[
                                                        'confidence'])
                                                .abs())
                                            .reduce((a, b) => a < b ? a : b),
                                orElse: () => {},
                              )
                          ? Colors.red
                          : detection['isSpecifiedObject']
                              ? Colors.yellow
                              : Colors.green,
                      width: 2,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        top: 0,
                        left: 0,
                        child: Container(
                          color: detection ==
                                  _detections.firstWhere(
                                    (d) =>
                                        d['isSpecifiedObject'] &&
                                        (d['confidence'] -
                                                    widget.detectedObject[
                                                        'confidence'])
                                                .abs() ==
                                            _detections
                                                .where((d) =>
                                                    d['isSpecifiedObject'])
                                                .map((d) => (d['confidence'] -
                                                        widget.detectedObject[
                                                            'confidence'])
                                                    .abs())
                                                .reduce(
                                                    (a, b) => a < b ? a : b),
                                    orElse: () => {},
                                  )
                              ? Colors.red
                              : detection['isSpecifiedObject']
                                  ? Colors.yellow
                                  : Colors.green,
                          padding: EdgeInsets.all(2),
                          child: Text(
                            detection['name'],
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
                        // Reinitialize camera and reset detection state after returning from album
                        _initializeCamera(_currentCamera);
                        setState(() {
                          _detections = [];
                          _specifiedObjectDetected = false;
                        });
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
                      icon: Icon(Icons.arrow_forward),
                      color: Colors.white,
                      onPressed: () {
                        // Add functionality for next step
                      },
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
                icon: Icon(_isRecording
                    ? Icons.stop
                    : Icons.fiber_manual_record_outlined),
                color: Colors.black,
                iconSize: 35,
                onPressed: _toggleRecordVideo,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CustomFunctionBarRecord extends StatelessWidget {
  final VoidCallback onSwitchCamera;
  final VoidCallback onToggleFlash;
  final VoidCallback onToggleLocationSearch;
  final bool isFlashOn;
  final List<String> identifiedObjects;
  final bool isLocationSearching;

  const CustomFunctionBarRecord({
    required this.onSwitchCamera,
    required this.onToggleFlash,
    required this.isFlashOn,
    required this.onToggleLocationSearch,
    required this.isLocationSearching,
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
                icon: Icon(
                  isLocationSearching
                      ? Icons.location_searching
                      : Icons.location_disabled,
                  color: Colors.white,
                ),
                onPressed: onToggleLocationSearch,
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
