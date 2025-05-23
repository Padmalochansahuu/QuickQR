// app_services.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p; 
import 'package:uuid/uuid.dart';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart'; 


enum ScanType {
  url,
  text,
  contact,
  wifi,
  other,
}

extension ScanTypeExtension on ScanType {
  String get displayName {
    switch (this) {
      case ScanType.url: return "URL";
      case ScanType.text: return "Text";
      case ScanType.contact: return "Contact";
      case ScanType.wifi: return "Wi-Fi";
      case ScanType.other:
      default: return "Other";
    }
  }

  IconData get displayIcon {
    switch (this) {
      case ScanType.url: return Icons.link;
      case ScanType.text: return Icons.text_fields;
      case ScanType.contact: return Icons.person_outline;
      case ScanType.wifi: return Icons.wifi;
      case ScanType.other:
      default: return Icons.qr_code_scanner;
    }
  }
}

class ScanItem {
  final String id;
  final String data;
  final DateTime timestamp;
  final ScanType type;

  ScanItem({
    String? id,
    required this.data,
    required this.timestamp,
    required this.type,
  }) : id = id ?? const Uuid().v4();

  factory ScanItem.fromMap(Map<String, dynamic> map) {
    return ScanItem(
      id: map['id'] as String,
      data: map['data'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
      type: ScanType.values.firstWhere(
            (e) => e.toString() == map['type'],
        orElse: () => ScanType.other, 
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'data': data,
      'timestamp': timestamp.toIso8601String(),
      'type': type.toString(), 
    };
  }

  static ScanType determineType(String data) {
    if (data.startsWith('http://') || data.startsWith('https://')) {
      return ScanType.url;
    } else if (data.toLowerCase().startsWith('begin:vcard')) {
      return ScanType.contact;
    } else if (data.toLowerCase().startsWith('wifi:')) {
      return ScanType.wifi;
    }
    return ScanType.text;
  }

  IconData get icon => type.displayIcon;
  String get typeName => type.displayName;
}

// --- DatabaseHelper ---
class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;
  static const String _dbName = 'scansave.db';
  static const String _tableName = 'scans';

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = p.join(documentsDirectory.path, _dbName);
    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_tableName (
        id TEXT PRIMARY KEY,
        data TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        type TEXT NOT NULL
      )
    ''');
  }

  Future<int> addScan(ScanItem scan) async {
    final db = await database;
    return await db.insert(_tableName, scan.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<ScanItem>> getScans() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      orderBy: 'timestamp DESC', 
    );
    return List.generate(maps.length, (i) {
      return ScanItem.fromMap(maps[i]);
    });
  }

  Future<int> deleteScan(String id) async {
    final db = await database;
    return await db.delete(
      _tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> close() async {
    final db = await _database; 
    if (db != null && db.isOpen) {
      await db.close();
      _database = null;
    }
  }
}


class CsvUtils {
  static Future<void> exportScansToCsv(List<ScanItem> scans, BuildContext context) async {
    if (scans.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No scans to export.')),
        );
      }
      return;
    }

    List<List<dynamic>> rows = [];

    rows.add(['ID', 'Data', 'Timestamp', 'Type']);

    for (var scan in scans) {
      rows.add([scan.id, scan.data, scan.timestamp.toIso8601String(), scan.typeName]);
    }

    String csvString = const ListToCsvConverter().convert(rows);

    try {
      final directory = await getTemporaryDirectory();
      final path = p.join(directory.path, 'scansave_export_${DateTime.now().millisecondsSinceEpoch}.csv');
      final file = File(path);
      await file.writeAsString(csvString);

      
      final xFile = XFile(path);

      await Share.shareXFiles([xFile], text: 'ScanSave Data Export');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CSV export initiated.')),
        );
      }
    } catch (e) {
       if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error exporting CSV: $e')),
        );
      }
    }
  }
}