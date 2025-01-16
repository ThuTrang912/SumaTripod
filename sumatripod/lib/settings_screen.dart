import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'bluetooth_connection_manager.dart';

class SettingsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
        backgroundColor: Color(0xFFFFA726),
      ),
      body: ListView(
        children: <Widget>[
          ListTile(
            leading: Icon(Icons.bluetooth),
            title: Text('Bluetooth Connection'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => BluetoothSettingsScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}

class BluetoothSettingsScreen extends StatefulWidget {
  @override
  _BluetoothSettingsScreenState createState() =>
      _BluetoothSettingsScreenState();
}

class _BluetoothSettingsScreenState extends State<BluetoothSettingsScreen> {
  List<BluetoothDevice> devicesList = [];
  BluetoothState _bluetoothState = BluetoothState.UNKNOWN;

  @override
  void initState() {
    super.initState();
    requestPermissions();
    FlutterBluetoothSerial.instance.state.then((state) {
      setState(() {
        _bluetoothState = state;
      });
    });

    FlutterBluetoothSerial.instance
        .onStateChanged()
        .listen((BluetoothState state) {
      setState(() {
        _bluetoothState = state;
      });
    });

    checkBluetooth();
  }

  void requestPermissions() async {
    await Permission.bluetooth.request();
    await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();
    await Permission.location.request();
  }

  void checkBluetooth() async {
    bool isEnabled = await FlutterBluetoothSerial.instance.isEnabled ?? false;
    if (!isEnabled) {
      await FlutterBluetoothSerial.instance.requestEnable();
    }
    startScan();
  }

  void startScan() async {
    devicesList = await FlutterBluetoothSerial.instance.getBondedDevices();
    print("Bonded devices: ${devicesList.length}");
    for (var device in devicesList) {
      print("Device: ${device.name}, Address: ${device.address}");
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bluetoothManager = Provider.of<BluetoothConnectionManager>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Bluetooth Connection'),
        backgroundColor: Color(0xFFFFA726),
      ),
      body: devicesList.isEmpty
          ? Center(child: Text('No bonded devices found'))
          : ListView.builder(
              itemCount: devicesList.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(devicesList[index].name ?? "Unknown device"),
                  subtitle: Text(devicesList[index].address),
                  trailing: bluetoothManager.connectedDevice != null &&
                          bluetoothManager.connectedDevice!.address ==
                              devicesList[index].address
                      ? Icon(Icons.check, color: Colors.green)
                      : null,
                  onTap: () {
                    if (bluetoothManager.connectedDevice != null &&
                        bluetoothManager.connectedDevice!.address ==
                            devicesList[index].address) {
                      bluetoothManager.disconnect();
                    } else {
                      bluetoothManager.connectToDevice(devicesList[index]);
                    }
                  },
                );
              },
            ),
    );
  }
}
