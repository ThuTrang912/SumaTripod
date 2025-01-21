import 'package:flutter/material.dart';
import 'dart:io';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:permission_handler/permission_handler.dart';

class VideoAlbum extends StatefulWidget {
  final bool refresh;

  const VideoAlbum({super.key, this.refresh = false});

  @override
  _VideoAlbumState createState() => _VideoAlbumState();
}

class _VideoAlbumState extends State<VideoAlbum> with WidgetsBindingObserver {
  Future<void> _deleteAllVideos() async {
    for (var video in _videos) {
      await video.delete();
    }
    setState(() {
      _videos.clear();
      _thumbnails.clear();
    });
    print('All videos deleted');
  }

  List<File> _videos = [];
  Map<String, String> _thumbnails = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requestStoragePermission();
    _loadVideos();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh the video list when the app resumes
      _loadVideos();
    }
  }

  Future<void> _requestStoragePermission() async {
    var status = await Permission.storage.request();
    if (status.isGranted) {
      print('Storage permission granted');
    } else {
      print('Storage permission denied');
    }
  }

  Future<void> _ensureVideoDirectoryExists() async {
    final appDir = await getExternalStorageDirectory();
    final savePath = '${appDir?.path}/my_videos/';
    final directory = Directory(savePath);

    if (!await directory.exists()) {
      await directory.create(recursive: true);
      print('Video directory created: $savePath');
    }
  }

  Future<void> _loadVideos() async {
    await _ensureVideoDirectoryExists();

    final appDir = await getExternalStorageDirectory();
    final savePath = '${appDir?.path}/my_videos/';
    final directory = Directory(savePath);

    setState(() {
      _videos = directory
          .listSync()
          .where((item) => item.path.endsWith(".mp4"))
          .map((item) => File(item.path))
          .toList();

      // Sort videos by last modified time in descending order
      _videos
          .sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    });

    print('Videos found: ${_videos.length}');

    for (var video in _videos) {
      _thumbnails[video.path] = await _getVideoThumbnail(video.path);
    }

    setState(() {});
  }

  Future<String> _getVideoThumbnail(String videoPath) async {
    final thumbnailDir = await getApplicationDocumentsDirectory();
    final thumbnailPath = '${thumbnailDir.path}/thumbnails';
    final thumbnailFile = File('$thumbnailPath/${videoPath.hashCode}.jpg');

    if (!await thumbnailFile.exists()) {
      await VideoThumbnail.thumbnailFile(
        video: videoPath,
        thumbnailPath: thumbnailPath,
        imageFormat: ImageFormat.JPEG,
        maxHeight: 100,
        quality: 75,
      );
    }

    return thumbnailFile.path;
  }

  Future<void> _deleteVideo(File video) async {
    if (await video.exists()) {
      await video.delete();
      setState(() {
        _videos.remove(video);
        _thumbnails.remove(video.path);
      });
      print('Video deleted: ${video.path}');
    }
  }

  Future<void> _renameVideo(File video) async {
    final newName = await _showRenameDialog(video);
    if (newName != null && newName.isNotEmpty) {
      final newPath = video.parent.path + '/' + newName + '.mp4';
      await video.rename(newPath);
      setState(() {
        _loadVideos();
      });
      print('Video renamed to: $newPath');
    }
  }

  Future<String?> _showRenameDialog(File video) async {
    String newName = '';
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Rename Video'),
          content: TextField(
            onChanged: (value) {
              newName = value;
            },
            decoration: InputDecoration(hintText: "Enter new name"),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('Rename'),
              onPressed: () {
                Navigator.of(context).pop(newName);
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Video Album'),
        backgroundColor: Color(0xFFFFA726),
        actions: [
          IconButton(
            icon: Icon(Icons.delete),
            onPressed: () async {
              await _deleteAllVideos();
            },
          ),
        ],
      ),
      body: _videos.isEmpty
          ? Center(child: Text('No videos found'))
          : ListView.builder(
              itemCount: _videos.length,
              itemBuilder: (context, index) {
                return ListTile(
                  leading: _thumbnails.containsKey(_videos[index].path)
                      ? Image.file(
                          File(_thumbnails[_videos[index].path]!),
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          width: 100,
                          height: 100,
                          color: Colors.grey,
                          child: Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                  title: Text(_videos[index].path.split('/').last),
                  subtitle: Text(
                      'Date: ${DateFormat('yyyy-MM-dd').format(File(_videos[index].path).lastModifiedSync())}'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (String result) {
                      if (result == 'Delete') {
                        _deleteVideo(_videos[index]);
                      } else if (result == 'Rename') {
                        _renameVideo(_videos[index]);
                      }
                    },
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(
                        value: 'Delete',
                        child: Text('Delete'),
                      ),
                      const PopupMenuItem<String>(
                        value: 'Rename',
                        child: Text('Rename'),
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => VideoPlayerScreen(
                          videoFile: _videos[index],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

class VideoPlayerScreen extends StatefulWidget {
  final File videoFile;

  VideoPlayerScreen({required this.videoFile});

  @override
  _VideoPlayerScreenState createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.videoFile)
      ..initialize().then((_) {
        setState(() {});
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Video Player'),
        backgroundColor: Color(0xFFFFA726),
      ),
      body: Center(
        child: _controller.value.isInitialized
            ? Column(
                children: [
                  AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: VideoPlayer(_controller),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      'Date: ${DateFormat('yyyy-MM-dd').format(File(widget.videoFile.path).lastModifiedSync())}',
                      style: TextStyle(color: Colors.black, fontSize: 16),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      'Start Time: ${DateFormat('HH:mm:ss').format(File(widget.videoFile.path).lastModifiedSync())}',
                      style: TextStyle(color: Colors.black, fontSize: 16),
                    ),
                  ),
                ],
              )
            : CircularProgressIndicator(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {
            _controller.value.isPlaying
                ? _controller.pause()
                : _controller.play();
          });
        },
        backgroundColor: Colors.orange, // Set the background color to orange
        child: Icon(
          _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
          color: Colors.black, // Set the icon color to white
        ),
      ),
    );
  }
}
