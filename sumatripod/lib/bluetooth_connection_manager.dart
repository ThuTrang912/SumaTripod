import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

class BluetoothConnectionManager extends ChangeNotifier {
  BluetoothDevice? _connectedDevice;
  BluetoothConnection? _connection;

  BluetoothDevice? get connectedDevice => _connectedDevice;

  Future<void> connectToDevice(BluetoothDevice device) async {
    try {
      _connection = await BluetoothConnection.toAddress(device.address);
      _connectedDevice = device;
      notifyListeners();
      print('Connected to the device');
    } catch (e) {
      print("Error connecting to device: $e");
    }
  }

  void disconnect() {
    _connection?.dispose();
    _connectedDevice = null;
    notifyListeners();
  }

  void sendGimbalCommand(String command) {
    if (_connection != null && _connection!.isConnected) {
      _connection!.output.add(Uint8List.fromList(utf8.encode(command)));
      _connection!.output.allSent;
    }
  }

  Future<bool> isConnected() async {
    return _connection != null && _connection!.isConnected;
  }

  @override
  void dispose() {
    _connection?.dispose();
    super.dispose();
  }
}
