import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';

class PrinterScreen extends StatefulWidget {
  const PrinterScreen({super.key});

  @override
  State<PrinterScreen> createState() => _PrinterScreenState();
}

class _PrinterScreenState extends State<PrinterScreen> {
  // Printer Type [bluetooth, usb, network]
  var defaultPrinterType = PrinterType.usb;
  var _isBle = false;
  var _reconnect = false;
  var _isConnected = false;
  var printerManager = PrinterManager.instance;
  var devices = <BluetoothPrinter>[];
  StreamSubscription<PrinterDevice>? _subscription;
  StreamSubscription<BTStatus>? _subscriptionBtStatus;
  StreamSubscription<USBStatus>? _subscriptionUsbStatus;
  BTStatus _currentStatus = BTStatus.none;
  // _currentUsbStatus is only supports on Android
  // ignore: unused_field
  USBStatus _currentUsbStatus = USBStatus.none;
  List<int>? pendingTask;
  String _ipAddress = '';
  String _port = '9100';
  final _ipController = TextEditingController();
  final _portController = TextEditingController();
  BluetoothPrinter? selectedPrinter;

  @override
  void initState() {
    if (Platform.isWindows) defaultPrinterType = PrinterType.usb;
    super.initState();
    _portController.text = _port;
    _scan();

    // subscription to listen change status of bluetooth connection
    _subscriptionBtStatus =
        PrinterManager.instance.stateBluetooth.listen((status) {
      log(' ----------------- status bt $status ------------------ ');
      _currentStatus = status;
      if (status == BTStatus.connected) {
        setState(() {
          _isConnected = true;
        });
      }
      if (status == BTStatus.none) {
        setState(() {
          _isConnected = false;
        });
      }
      if (status == BTStatus.connected && pendingTask != null) {
        if (Platform.isAndroid) {
          Future.delayed(const Duration(milliseconds: 1000), () {
            PrinterManager.instance
                .send(type: PrinterType.bluetooth, bytes: pendingTask!);
            pendingTask = null;
          });
        } else if (Platform.isIOS) {
          PrinterManager.instance
              .send(type: PrinterType.bluetooth, bytes: pendingTask!);
          pendingTask = null;
        }
      }
    });
    //  PrinterManager.instance.stateUSB is only supports on Android
    _subscriptionUsbStatus = PrinterManager.instance.stateUSB.listen((status) {
      log(' ----------------- status usb $status ------------------ ');
      _currentUsbStatus = status;
      if (Platform.isAndroid) {
        if (status == USBStatus.connected && pendingTask != null) {
          Future.delayed(const Duration(milliseconds: 1000), () {
            PrinterManager.instance
                .send(type: PrinterType.usb, bytes: pendingTask!);
            pendingTask = null;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscriptionBtStatus?.cancel();
    _subscriptionUsbStatus?.cancel();
    _portController.dispose();
    _ipController.dispose();
    super.dispose();
  }

  // method to scan devices according PrinterType
  void _scan() {
    devices.clear();
    _subscription = printerManager
        .discovery(type: defaultPrinterType, isBle: _isBle)
        .listen((device) {
      devices.add(BluetoothPrinter(
        deviceName: device.name,
        address: device.address,
        isBle: _isBle,
        vendorId: device.vendorId,
        productId: device.productId,
        typePrinter: defaultPrinterType,
      ));
      setState(() {});
    });
  }

  void setPort(String value) {
    if (value.isEmpty) value = '9100';
    _port = value;
    var device = BluetoothPrinter(
      deviceName: value,
      address: _ipAddress,
      port: _port,
      typePrinter: PrinterType.network,
      state: false,
    );
    selectDevice(device);
  }

  void setIpAddress(String value) {
    _ipAddress = value;
    var device = BluetoothPrinter(
      deviceName: value,
      address: _ipAddress,
      port: _port,
      typePrinter: PrinterType.network,
      state: false,
    );
    selectDevice(device);
  }

  void selectDevice(BluetoothPrinter device) async {
    if (selectedPrinter != null) {
      if ((device.address != selectedPrinter!.address) ||
          (device.typePrinter == PrinterType.usb &&
              selectedPrinter!.vendorId != device.vendorId)) {
        await PrinterManager.instance
            .disconnect(type: selectedPrinter!.typePrinter);
      }
    }

    selectedPrinter = device;
    setState(() {});
  }

  Future _printDiagnostic() async {
    try {
      List<int> bytes = [];

      // Initialize with specific profile for thermal printers
      final profile = await CapabilityProfile.load(name: 'default');
      final generator = Generator(PaperSize.mm80, profile);

      // Initialize printer
      bytes += generator.reset();
      bytes += [0x1B, 0x40]; // ESC @ - Initialize printer
      bytes += [0x1B, 0x21, 0x00]; // ESC ! 0 - Normal text mode
      bytes += generator.setGlobalCodeTable('CP437');
      bytes += [0x1B, 0x74, 0x00]; // Select character code table
      bytes += [0x1B, 0x32]; // ESC 2 - Default line spacing

      // Store Header
      bytes += generator.text('RESTRO',
          styles: const PosStyles(
            align: PosAlign.center,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
            bold: true,
          ));
      bytes += generator.feed(1);

      // Store Address and Info
      bytes += generator.text('RESTORAN AMINAH BISTRO',
          styles: const PosStyles(align: PosAlign.center));
      bytes += generator.text('JM0868896-K',
          styles: const PosStyles(align: PosAlign.center));
      bytes += generator.feed(1);

      // Receipt Info
      String now = DateTime.now().toString().substring(0, 19);
      bytes += generator.text('Date: $now',
          styles: const PosStyles(align: PosAlign.left));
      bytes += generator.text(
          'Receipt #: INV-${DateTime.now().millisecondsSinceEpoch.toString().substring(5, 13)}',
          styles: const PosStyles(align: PosAlign.left));
      bytes += generator.feed(1);

      // Divider
      bytes += generator.text('--------------------------------',
          styles: const PosStyles(align: PosAlign.center));
      bytes += generator.feed(1);

      // Column Headers - Added spaces for padding
      bytes += generator.row([
        PosColumn(text: 'Item          ', width: 6),
        PosColumn(
            text: ' Qty  ',
            width: 2,
            styles: const PosStyles(align: PosAlign.right)),
        PosColumn(
            text: ' Price  ',
            width: 2,
            styles: const PosStyles(align: PosAlign.right)),
        PosColumn(
            text: ' Total',
            width: 2,
            styles: const PosStyles(align: PosAlign.right)),
      ]);

      // Items - Added spaces for padding
      bytes += generator.row([
        PosColumn(text: 'Product 1     ', width: 6),
        PosColumn(
            text: '  2   ',
            width: 2,
            styles: const PosStyles(align: PosAlign.right)),
        PosColumn(
            text: ' 10.00 ',
            width: 2,
            styles: const PosStyles(align: PosAlign.right)),
        PosColumn(
            text: ' 20.00',
            width: 2,
            styles: const PosStyles(align: PosAlign.right)),
      ]);

      bytes += generator.row([
        PosColumn(text: 'Product 2     ', width: 6),
        PosColumn(
            text: '  1   ',
            width: 2,
            styles: const PosStyles(align: PosAlign.right)),
        PosColumn(
            text: ' 15.00 ',
            width: 2,
            styles: const PosStyles(align: PosAlign.right)),
        PosColumn(
            text: ' 15.00',
            width: 2,
            styles: const PosStyles(align: PosAlign.right)),
      ]);

      bytes += generator.feed(1);

      // Subtotal, Tax, Total - Added spaces for padding
      bytes += generator.row([
        PosColumn(
            text: 'Subtotal:      ',
            width: 8,
            styles: const PosStyles(align: PosAlign.right)),
        PosColumn(
            text: '    35.00',
            width: 4,
            styles: const PosStyles(align: PosAlign.right)),
      ]);

      bytes += generator.row([
        PosColumn(
            text: 'Tax (10%):     ',
            width: 8,
            styles: const PosStyles(align: PosAlign.right)),
        PosColumn(
            text: '     3.50',
            width: 4,
            styles: const PosStyles(align: PosAlign.right)),
      ]);

      bytes += generator.row([
        PosColumn(
          text: 'TOTAL:         ',
          width: 8,
          styles: const PosStyles(
            align: PosAlign.right,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
          ),
        ),
        PosColumn(
          text: '    38.50',
          width: 4,
          styles: const PosStyles(
            align: PosAlign.right,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
          ),
        ),
      ]);
      bytes += generator.feed(1);

      // Payment Method
      bytes += generator.text('Payment Method: CASH',
          styles: const PosStyles(align: PosAlign.center));
      bytes += generator.feed(1);

      // QR Code
      bytes += generator.qrcode('https://orivios.com/', size: QRSize.Size5);
      bytes += generator.feed(1);

      // Footer
      bytes += generator.text('Thank you for your purchase!',
          styles: const PosStyles(align: PosAlign.center, bold: true));
      bytes += generator.text('Please come again',
          styles: const PosStyles(align: PosAlign.center));
      bytes += generator.feed(1);

      // Return Policy
      bytes += generator.text('Exchange within 7 days',
          styles: const PosStyles(align: PosAlign.center));
      bytes += generator.text('with original receipt',
          styles: const PosStyles(align: PosAlign.center));

      // Add final feeds before the single cut
      bytes += generator.feed(3);
      bytes += generator.cut();

      log("Generated ${bytes.length} bytes for printing");

      if (selectedPrinter == null) {
        log("No printer selected");
        return;
      }

      // Disconnect first to ensure clean state
      await printerManager.disconnect(type: PrinterType.usb);
      await Future.delayed(const Duration(milliseconds: 1000));

      // Connect with specific settings
      await printerManager.connect(
        type: PrinterType.usb,
        model: UsbPrinterInput(
          name: selectedPrinter!.deviceName,
          productId: selectedPrinter!.productId,
          vendorId: selectedPrinter!.vendorId,
        ),
      );

      await Future.delayed(const Duration(milliseconds: 1000));

      // Send data in chunks
      const int chunkSize = 64;
      for (var i = 0; i < bytes.length; i += chunkSize) {
        var end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
        var chunk = bytes.sublist(i, end);

        await printerManager.send(
          type: PrinterType.usb,
          bytes: chunk,
        );

        await Future.delayed(const Duration(milliseconds: 50));
      }

      log("Print command sent successfully");
    } catch (e, stackTrace) {
      log("Error during printing: $e");
      log("Stack trace: $stackTrace");
    }
  }

  // conectar dispositivo
  Future<bool> _connectDevice() async {
    if (selectedPrinter == null) return false;

    try {
      log("Attempting to connect to ${selectedPrinter!.deviceName}");

      switch (selectedPrinter!.typePrinter) {
        case PrinterType.usb:
          await printerManager.connect(
            type: PrinterType.usb,
            model: UsbPrinterInput(
              name: selectedPrinter!.deviceName,
              productId: selectedPrinter!.productId,
              vendorId: selectedPrinter!.vendorId,
            ),
          );
          setState(() => _isConnected = true);
          break;

        case PrinterType.bluetooth:
          await printerManager.connect(
            type: PrinterType.bluetooth,
            model: BluetoothPrinterInput(
              name: selectedPrinter!.deviceName,
              address: selectedPrinter!.address!,
              isBle: selectedPrinter!.isBle ?? false,
              autoConnect: _reconnect,
            ),
          );
          // For Bluetooth, _isConnected is managed by the status listener
          break;

        case PrinterType.network:
          await printerManager.connect(
            type: PrinterType.network,
            model: TcpPrinterInput(
              ipAddress: selectedPrinter!.address!,
              port: int.tryParse(selectedPrinter!.port ?? '9100') ?? 9100,
            ),
          );
          setState(() => _isConnected = true);
          break;
      }

      log("Connection successful");
      return true;
    } catch (e) {
      log("Error during connection: $e");
      setState(() => _isConnected = false);
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter Pos Plugin Platform example app'),
      ),
      body: Center(
        child: Container(
          height: double.infinity,
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: selectedPrinter == null || _isConnected
                              ? null
                              : () {
                                  _connectDevice();
                                },
                          child: const Text("Connect",
                              textAlign: TextAlign.center),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: selectedPrinter == null || !_isConnected
                              ? null
                              : () {
                                  if (selectedPrinter != null) {
                                    printerManager.disconnect(
                                        type: selectedPrinter!.typePrinter);
                                  }
                                  setState(() {
                                    _isConnected = false;
                                  });
                                },
                          child: const Text("Disconnect",
                              textAlign: TextAlign.center),
                        ),
                      ),
                    ],
                  ),
                ),
                DropdownButtonFormField<PrinterType>(
                  value: defaultPrinterType,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(
                      Icons.print,
                      size: 24,
                    ),
                    labelText: "Type Printer Device",
                    labelStyle: TextStyle(fontSize: 18.0),
                    focusedBorder: InputBorder.none,
                    enabledBorder: InputBorder.none,
                  ),
                  items: <DropdownMenuItem<PrinterType>>[
                    if (Platform.isAndroid || Platform.isIOS)
                      const DropdownMenuItem(
                        value: PrinterType.bluetooth,
                        child: Text("bluetooth"),
                      ),
                    if (Platform.isAndroid || Platform.isWindows)
                      const DropdownMenuItem(
                        value: PrinterType.usb,
                        child: Text("usb"),
                      ),
                    const DropdownMenuItem(
                      value: PrinterType.network,
                      child: Text("Wifi"),
                    ),
                  ],
                  onChanged: (PrinterType? value) {
                    setState(() {
                      if (value != null) {
                        setState(() {
                          defaultPrinterType = value;
                          selectedPrinter = null;
                          _isBle = false;
                          _isConnected = false;
                          _scan();
                        });
                      }
                    });
                  },
                ),
                Visibility(
                  visible: defaultPrinterType == PrinterType.bluetooth &&
                      Platform.isAndroid,
                  child: SwitchListTile.adaptive(
                    contentPadding:
                        const EdgeInsets.only(bottom: 20.0, left: 20),
                    title: const Text(
                      "This device supports ble (low energy)",
                      textAlign: TextAlign.start,
                      style: TextStyle(fontSize: 19.0),
                    ),
                    value: _isBle,
                    onChanged: (bool? value) {
                      setState(() {
                        _isBle = value ?? false;
                        _isConnected = false;
                        selectedPrinter = null;
                        _scan();
                      });
                    },
                  ),
                ),
                Visibility(
                  visible: defaultPrinterType == PrinterType.bluetooth &&
                      Platform.isAndroid,
                  child: SwitchListTile.adaptive(
                    contentPadding:
                        const EdgeInsets.only(bottom: 20.0, left: 20),
                    title: const Text(
                      "reconnect",
                      textAlign: TextAlign.start,
                      style: TextStyle(fontSize: 19.0),
                    ),
                    value: _reconnect,
                    onChanged: (bool? value) {
                      setState(() {
                        _reconnect = value ?? false;
                      });
                    },
                  ),
                ),
                Column(
                    children: devices
                        .map(
                          (device) => ListTile(
                            title: Text('${device.deviceName}'),
                            subtitle: Platform.isAndroid &&
                                    defaultPrinterType == PrinterType.usb
                                ? null
                                : Visibility(
                                    visible: !Platform.isWindows,
                                    child: Text("${device.address}")),
                            onTap: () {
                              // do something
                              selectDevice(device);
                            },
                            leading: selectedPrinter != null &&
                                    ((device.typePrinter == PrinterType.usb &&
                                                Platform.isWindows
                                            ? device.deviceName ==
                                                selectedPrinter!.deviceName
                                            : device.vendorId != null &&
                                                selectedPrinter!.vendorId ==
                                                    device.vendorId) ||
                                        (device.address != null &&
                                            selectedPrinter!.address ==
                                                device.address))
                                ? const Icon(
                                    Icons.check,
                                    color: Colors.green,
                                  )
                                : null,
                            trailing: OutlinedButton(
                              onPressed: selectedPrinter == null ||
                                      device.deviceName !=
                                          selectedPrinter?.deviceName
                                  ? null
                                  : () async {
                                      try {
                                        if (selectedPrinter != null) {
                                          await _connectDevice();
                                          await _printDiagnostic();
                                        }
                                      } catch (e) {
                                        log("Error: $e");
                                      }
                                    },
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                    vertical: 2, horizontal: 20),
                                child: Text("Print test ticket",
                                    textAlign: TextAlign.center),
                              ),
                            ),
                          ),
                        )
                        .toList()),
                Visibility(
                  visible: defaultPrinterType == PrinterType.network &&
                      Platform.isWindows,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10.0),
                    child: TextFormField(
                      controller: _ipController,
                      keyboardType:
                          const TextInputType.numberWithOptions(signed: true),
                      decoration: const InputDecoration(
                        label: Text("Ip Address"),
                        prefixIcon: Icon(Icons.wifi, size: 24),
                      ),
                      onChanged: setIpAddress,
                    ),
                  ),
                ),
                Visibility(
                  visible: defaultPrinterType == PrinterType.network &&
                      Platform.isWindows,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10.0),
                    child: TextFormField(
                      controller: _portController,
                      keyboardType:
                          const TextInputType.numberWithOptions(signed: true),
                      decoration: const InputDecoration(
                        label: Text("Port"),
                        prefixIcon: Icon(Icons.numbers_outlined, size: 24),
                      ),
                      onChanged: setPort,
                    ),
                  ),
                ),
                Visibility(
                  visible: defaultPrinterType == PrinterType.network &&
                      Platform.isWindows,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10.0),
                    child: OutlinedButton(
                      onPressed: () async {
                        if (_ipController.text.isNotEmpty) {
                          setIpAddress(_ipController.text);
                        }
                        try {
                          if (selectedPrinter != null) {
                            await _connectDevice();
                            await _printDiagnostic();
                          }
                        } catch (e) {
                          log("Error: $e");
                        }
                      },
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(vertical: 4, horizontal: 50),
                        child: Text("Print test ticket",
                            textAlign: TextAlign.center),
                      ),
                    ),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BluetoothPrinter {
  int? id;
  String? deviceName;
  String? address;
  String? port;
  String? vendorId;
  String? productId;
  bool? isBle;

  PrinterType typePrinter;
  bool? state;

  BluetoothPrinter(
      {this.deviceName,
      this.address,
      this.port,
      this.state,
      this.vendorId,
      this.productId,
      this.typePrinter = PrinterType.bluetooth,
      this.isBle = false});
}
