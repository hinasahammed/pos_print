import 'dart:convert';

import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import 'package:pos_print/printer_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrinterStorage {
  static const String _key = 'saved_printers';

  static Future<void> savePrinter(BluetoothPrinter printer) async {
    final prefs = await SharedPreferences.getInstance();
    final printerMap = _printerToMap(printer);
    final identifier = _getPrinterIdentifier(printer);

    // Get existing printers
    Map<String, dynamic> savedPrinters = await _getSavedPrinters();

    // Update or add the printer
    savedPrinters[identifier] = printerMap;

    // Save back to preferences
    await prefs.setString(_key, jsonEncode(savedPrinters));
  }

  static Future<void> deletePrinter(BluetoothPrinter printer) async {
    final prefs = await SharedPreferences.getInstance();
    final identifier = _getPrinterIdentifier(printer);

    // Get existing printers
    Map<String, dynamic> savedPrinters = await _getSavedPrinters();

    // Remove the printer
    savedPrinters.remove(identifier);

    // Save back to preferences
    await prefs.setString(_key, jsonEncode(savedPrinters));
  }

  static Future<List<BluetoothPrinter>> loadSavedPrinters() async {
    Map<String, dynamic> savedPrinters = await _getSavedPrinters();

    return savedPrinters.values
        .map((printerMap) => _mapToPrinter(printerMap))
        .toList();
  }

  static Future<Map<String, dynamic>> _getSavedPrinters() async {
    final prefs = await SharedPreferences.getInstance();
    final String? savedData = prefs.getString(_key);

    if (savedData == null) {
      return {};
    }

    return Map<String, dynamic>.from(jsonDecode(savedData));
  }

  static String _getPrinterIdentifier(BluetoothPrinter printer) {
    // Use address for bluetooth/network printers, deviceName+vendorId for USB
    return printer.address ?? '${printer.deviceName}_${printer.vendorId}';
  }

  static Map<String, dynamic> _printerToMap(BluetoothPrinter printer) {
    return {
      'deviceName': printer.deviceName,
      'address': printer.address,
      'port': printer.port,
      'vendorId': printer.vendorId,
      'productId': printer.productId,
      'isBle': printer.isBle,
      'typePrinter': printer.typePrinter.toString(),
      'state': printer.state,
    };
  }

  static BluetoothPrinter _mapToPrinter(Map<String, dynamic> map) {
    return BluetoothPrinter(
      deviceName: map['deviceName'],
      address: map['address'],
      port: map['port'],
      vendorId: map['vendorId'],
      productId: map['productId'],
      isBle: map['isBle'],
      typePrinter: PrinterType.values.firstWhere(
        (e) => e.toString() == map['typePrinter'],
        orElse: () => PrinterType.bluetooth,
      ),
      state: map['state'],
    );
  }
}
