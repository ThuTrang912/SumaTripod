import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'bluetooth_connection_manager.dart';
import 'recognize_camera.dart';
import 'settings_screen.dart';
import 'video_album.dart'; // Import the VideoAlbum screen
import 'package:camera/camera.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => BluetoothConnectionManager(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false, // Disable the debug banner
        theme: ThemeData(
          primarySwatch: Colors.orange, // Set the default color theme
          progressIndicatorTheme: ProgressIndicatorThemeData(
            color: Colors
                .black, // Set the default color for CircularProgressIndicator
          ),
          textTheme: TextTheme(
            bodyLarge: TextStyle(
                color: Colors.black), // Set default text color to black
            bodyMedium: TextStyle(
                color: Colors.black), // Set default text color to black
            labelLarge: TextStyle(
                color: Colors.black), // Set default button text color to black
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: Colors
                  .black, // Set default text color for TextButton to black
            ),
          ),
        ),
        home: Scaffold(
          body: GetStartedScreen(),
        ),
      ),
    );
  }
}

class GetStartedScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Color(0xFFFFA726),
        actions: [
          PopupMenuButton<String>(
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
      ),
      body: Container(
        color: Color(0xFFFFA726), // orange background color
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Spacer(flex: 2),
            Icon(
              Icons.crop_free,
              size: 100.0,
              color: Colors.black,
            ),
            Spacer(flex: 1),
            Text(
              'Get Started',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            SizedBox(height: 10),
            Text(
              'Capture joy, cherish moments.',
              style: TextStyle(
                fontSize: 16,
                color: Colors.black,
              ),
            ),
            Spacer(flex: 2),
            Align(
              alignment: Alignment.center,
              child: Container(
                margin: EdgeInsets.only(right: 0, bottom: 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(30.0),
                      child: GestureDetector(
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
                    ),
                    Container(
                      height: 150,
                      width: 150,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(100),
                        ),
                      ),
                      child: Align(
                        alignment: Alignment.bottomRight,
                        child: Padding(
                          padding: const EdgeInsets.all(40.0),
                          child: CircleAvatar(
                            backgroundColor: Colors.orange,
                            radius: 30,
                            child: IconButton(
                              icon: Icon(Icons.arrow_forward),
                              color: Colors.black,
                              onPressed: () async {
                                final cameras = await availableCameras();
                                final firstCamera = cameras.first;
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => RecognizeCamera(
                                        camera: firstCamera, isFlashOn: false),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
