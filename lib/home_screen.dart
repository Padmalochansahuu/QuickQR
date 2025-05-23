import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart'; 
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import 'app_services.dart';
import 'main.dart'; 

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<ScanItem> _allScans = [];
  List<ScanItem> _filteredScans = [];
  final TextEditingController _searchController = TextEditingController();
  String? _activeFilterTypeDisplayName;
  bool _isDarkMode = false;
  bool _isCameraPermissionGranted = false;
  bool _isScanning = false;

  bool _scanSuccessful = false;
  bool _scanFailed = false;
  Timer? _feedbackTimer;
  String _scanFeedbackMessage = '';

  final MobileScannerController _scannerController = MobileScannerController(

      );

  @override
  void initState() {
    super.initState();
    _loadScans();
    _searchController.addListener(_filterScans);
    _requestCameraPermission();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final platformBrightness = View.of(context).platformDispatcher.platformBrightness;
        _isDarkMode = platformBrightness == Brightness.dark;
        ScanSaveApp.of(context)?.changeTheme(_isDarkMode ? ThemeMode.dark : ThemeMode.light);
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterScans);
    _searchController.dispose();
    _scannerController.dispose();
    _feedbackTimer?.cancel();
    super.dispose();
  }

  Future<void> _requestCameraPermission() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }
    if (mounted) {
      setState(() {
        _isCameraPermissionGranted = status.isGranted;
      });
      if (!_isCameraPermissionGranted && (status.isDenied || status.isPermanentlyDenied)) {
        _showPermissionDeniedDialog();
      }
    }
  }

  void _showPermissionDeniedDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Camera Permission Required'),
        content: const Text('ScanSave needs camera access to scan QR codes. Please enable it in your phone settings for this app.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          TextButton(onPressed: () async {
            Navigator.of(context).pop();
            await openAppSettings();
          }, child: const Text('Open Settings')),
        ],
      ),
    );
  }

  Future<void> _loadScans() async {
    final scans = await _dbHelper.getScans();
    if (mounted) {
      setState(() {
        _allScans = scans;
        _filterScans();
      });
    }
  }

  void _filterScans() {
    String query = _searchController.text.toLowerCase();
    if (mounted) {
      setState(() {
        _filteredScans = _allScans.where((scan) {
          final typeMatch = _activeFilterTypeDisplayName == null ||
              scan.type.displayName == _activeFilterTypeDisplayName;
          final queryMatch = query.isEmpty ||
              scan.data.toLowerCase().contains(query) ||
              scan.typeName.toLowerCase().contains(query);
          return typeMatch && queryMatch;
        }).toList();
      });
    }
  }

  void _setActiveFilterType(String? displayName) {
    if (mounted) {
      setState(() {
        _activeFilterTypeDisplayName = displayName;
        _filterScans();
      });
    }
  }

  void _showScanFeedback(bool success, String message) {
    if (mounted) {
      setState(() {
        _scanSuccessful = success;
        _scanFailed = !success;
        _scanFeedbackMessage = message;
      });

      _feedbackTimer?.cancel();
      _feedbackTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _scanSuccessful = false;
            _scanFailed = false;
            _scanFeedbackMessage = '';
          });
        }
      });
    }
  }

  void _handleScanDetection(BarcodeCapture capture) {
    if (capture.barcodes.isEmpty || capture.barcodes.first.rawValue == null) {
      _showScanFeedback(false, 'No valid QR code found');
      return;
    }

    final String rawValue = capture.barcodes.first.rawValue!;
    
    if (rawValue.trim().isEmpty) {
      _showScanFeedback(false, 'Empty QR code data');
      return;
    }

    final ScanType type = ScanItem.determineType(rawValue);
    final newScan = ScanItem(data: rawValue, timestamp: DateTime.now(), type: type);

    _showScanFeedback(true, 'Scanned!');

    Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        _scannerController.stop();
        setState(() { _isScanning = false; });
      }
    });

    _dbHelper.addScan(newScan).then((_) {
      _loadScans();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${type.displayName} saved!')),
        );
        _showScanResultDialog(newScan, isNewScan: true);
      }
    }).catchError((error){
       if (mounted) {
        if (_isScanning) setState(() { _isScanning = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving scan: $error')),
        );
      }
    });
  }

  void _showScanResultDialog(ScanItem item, {bool isNewScan = false}) {
    if(!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(item.icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            Text('Scan Result (${item.typeName})'),
          ],
        ),
        content: SingleChildScrollView(
            child: SelectableText(item.data,
                style: TextStyle(
                    color: Theme.of(context).textTheme.bodyLarge?.color))),
        actions: <Widget>[
          TextButton(
            child: Text(isNewScan ? 'Done' : 'Close'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          ElevatedButton(
            onPressed: () {
              _copyToClipboard(item.data);
              if(!isNewScan) Navigator.of(context).pop();
            },
            child: const Text('Copy Data'),
          )
        ],
      ),
    );
  }

  Future<void> _deleteScan(String id) async {
    await _dbHelper.deleteScan(id);
    await _loadScans();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scan deleted'), duration: Duration(seconds: 2)),
      );
    }
  }

  void _shareScanData(String data) {
    Share.share(data, subject: 'Scanned Data from ScanSave');
  }

  void _copyToClipboard(String data) {
    Clipboard.setData(ClipboardData(text: data));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copied to clipboard!')),
      );
    }
  }

  void _exportData() async {
    if (mounted) {
      await CsvUtils.exportScansToCsv(_allScans, context);
    }
  }

  void _toggleTheme() {
    if (mounted) {
      setState(() {
        _isDarkMode = !_isDarkMode;
        ScanSaveApp.of(context)!.changeTheme(_isDarkMode ? ThemeMode.dark : ThemeMode.light);
      });
    }
  }

  void _triggerAutoFocus() {
    _showScanFeedback(false, 'Camera autofocus may have triggered');

  }

  Widget _buildFilterChips() {
    final scanTypeValues = ScanType.values;
    final chipTheme = Theme.of(context).chipTheme;

    return SizedBox(
      height: 55,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          ChoiceChip(
            label: const Text("All"),
            selected: _activeFilterTypeDisplayName == null,
            onSelected: (selected) {
              if (selected) _setActiveFilterType(null);
            },
          ),
          ...scanTypeValues.map((scanType) {
            final typeDisplayName = scanType.displayName;
            final bool isSelected = _activeFilterTypeDisplayName == typeDisplayName;
            return Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: ChoiceChip(
                label: Text(typeDisplayName),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) _setActiveFilterType(typeDisplayName);
                },
                avatar: Icon(
                  scanType.displayIcon,
                  color: isSelected
                      ? chipTheme.secondaryLabelStyle?.color ?? Theme.of(context).colorScheme.onPrimary
                      : chipTheme.labelStyle?.color ?? Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  size: chipTheme.iconTheme?.size ?? 18,
                ),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildScannerView() {
    if (!_isCameraPermissionGranted) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.no_photography_outlined, size: 60, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'Camera permission is required to scan QR codes. Please grant permission to continue.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Grant Permission'),
                onPressed: _requestCameraPermission,
              ),
            ],
          ),
        ),
      );
    }
    
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _scannerController,
          onDetect: _handleScanDetection,
          scanWindow: Rect.fromCenter(
            center: Offset(MediaQuery.of(context).size.width / 2, MediaQuery.of(context).size.height / 2.5),
            width: MediaQuery.of(context).size.width * 0.75,
            height: MediaQuery.of(context).size.width * 0.75,
          ),
        ),
        
        Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: MediaQuery.of(context).size.width * 0.75,
            height: MediaQuery.of(context).size.width * 0.75,
            decoration: BoxDecoration(
              border: Border.all(
                color: _scanSuccessful 
                  ? Colors.greenAccent 
                  : _scanFailed 
                    ? Colors.redAccent
                    : Colors.white.withOpacity(0.7), 
                width: _scanSuccessful || _scanFailed ? 3.5 : 2.5
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: _scanSuccessful || _scanFailed ? [
                BoxShadow(
                  color: (_scanSuccessful ? Colors.greenAccent : Colors.redAccent).withOpacity(0.2),
                  blurRadius: 8,
                  spreadRadius: 1,
                )
              ] : null,
            ),
            child: _scanSuccessful || _scanFailed ? Center(
              child: Icon(
                _scanSuccessful ? Icons.check_circle_outline_rounded : Icons.highlight_off_rounded,
                color: _scanSuccessful ? Colors.greenAccent : Colors.redAccent,
                size: 60,
              ),
            ) : null,
          ),
        ),
        
        if (_scanFeedbackMessage.isNotEmpty && !(_scanSuccessful || _scanFailed))
          Positioned(
            top: (MediaQuery.of(context).size.height / 2.5) + (MediaQuery.of(context).size.width * 0.75 / 2) + 20,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _scanFeedbackMessage,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        
        Positioned(
          top: MediaQuery.of(context).padding.top + 10,
          left: 10,
          child: IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 30),
            onPressed: () {
              if (mounted) {
                _scannerController.stop();
                setState(() { 
                  _isScanning = false; 
                  _scanSuccessful = false;
                  _scanFailed = false;
                  _scanFeedbackMessage = '';
                });
                _feedbackTimer?.cancel();
              }
            },
            style: IconButton.styleFrom(backgroundColor: Colors.black.withOpacity(0.3)),
          ),
        ),
        
        Positioned(
          top: MediaQuery.of(context).padding.top + 10,
          right: 10,
          child: IconButton(
            icon: const Icon(Icons.filter_center_focus_rounded, color: Colors.white, size: 28),
            onPressed: _triggerAutoFocus,
            style: IconButton.styleFrom(backgroundColor: Colors.black.withOpacity(0.3)),
            tooltip: 'Focus',
          ),
        ),
        
        Positioned(
          bottom: MediaQuery.of(context).padding.bottom + 32,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ValueListenableBuilder<MobileScannerState>(
                valueListenable: _scannerController,
                builder: (context, state, child) {
                  final TorchState currentTorchState = state.torchState; 
                  return IconButton(
                    style: IconButton.styleFrom(backgroundColor: Colors.black.withOpacity(0.3)),
                    icon: Icon(
                      currentTorchState == TorchState.on ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                      color: currentTorchState == TorchState.on ? Colors.amber : Colors.white,
                      size: 28,
                    ),
                    onPressed: () => _scannerController.toggleTorch(),
                  );
                }
              ),
              ValueListenableBuilder<MobileScannerState>(
                 valueListenable: _scannerController,
                 builder: (context, state, child) {
                  // CORRECTED: Use state.cameraDirection
                  final CameraFacing currentCameraFacing = state.cameraDirection; 
                  return IconButton(
                    style: IconButton.styleFrom(backgroundColor: Colors.black.withOpacity(0.3)),
                    icon: Icon(
                      currentCameraFacing == CameraFacing.front ? Icons.flip_camera_ios_rounded : Icons.flip_camera_ios_outlined,
                      color: Colors.white,
                      size: 28,
                    ),
                    onPressed: () => _scannerController.switchCamera(),
                  );
                }
              ),
            ],
          ),
        )
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (mounted) {
       final currentBrightness = Theme.of(context).brightness;
       _isDarkMode = currentBrightness == Brightness.dark;
    }

    return Scaffold(
      appBar: _isScanning ? null : AppBar(
        title: const Text('ScanSave'),
        actions: [
          IconButton(
            icon: Icon(_isDarkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            tooltip: 'Toggle Theme',
            onPressed: _toggleTheme,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'export_csv') {
                _exportData();
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'export_csv',
                child: ListTile(
                  leading: Icon(Icons.download_for_offline_outlined),
                  title: Text('Export to CSV'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search scans...',
                    prefixIcon: Icon(Icons.search, color: Theme.of(context).hintColor),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear, color: Theme.of(context).hintColor),
                            onPressed: () => _searchController.clear(),
                          )
                        : null,
                  ),
                ),
              ),
              _buildFilterChips(),
              Expanded(
                child: _filteredScans.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history_toggle_off_outlined, size: 80, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 32.0),
                              child: Text(
                                _allScans.isEmpty
                                 ? 'No scans yet. Tap the scan button below to start!'
                                 : 'No scans match your current filter or search.',
                                style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 90, left: 4, right: 4),
                        itemCount: _filteredScans.length,
                        itemBuilder: (context, index) {
                          final scan = _filteredScans[index];
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                child: Icon(
                                  scan.icon,
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                  size: 24,
                                ),
                              ),
                              title: Text(
                                scan.data,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: Theme.of(context).textTheme.titleMedium?.color),
                              ),
                              subtitle: Text(
                                "${scan.typeName} • ${DateFormat.yMMMd().add_jm().format(scan.timestamp)}",
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).textTheme.bodySmall?.color),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.copy_all_outlined, size: 20, color: Theme.of(context).iconTheme.color?.withOpacity(0.7)),
                                    tooltip: 'Copy',
                                    onPressed: () => _copyToClipboard(scan.data),
                                  ),
                                   IconButton(
                                    icon: Icon(Icons.share_outlined, size: 20, color: Theme.of(context).iconTheme.color?.withOpacity(0.7)),
                                    tooltip: 'Share',
                                    onPressed: () => _shareScanData(scan.data),
                                  ),
                                ],
                              ),
                              onTap: () => _showScanResultDialog(scan),
                              onLongPress: () {
                                showModalBottomSheet(
                                  context: context,
                                  backgroundColor: Theme.of(context).cardTheme.color ?? Theme.of(context).cardColor,
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                                  ),
                                  builder: (ctx) => Container(
                                    padding: const EdgeInsets.symmetric(horizontal:16, vertical: 20),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text("Actions for scan:", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 4),
                                        SelectableText(
                                          scan.data,
                                          style: Theme.of(context).textTheme.bodyMedium,
                                          minLines: 1,
                                          maxLines: 5,
                                        ),
                                        const SizedBox(height: 24),
                                        ListTile(
                                          leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                          title: const Text('Delete Scan', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w500)),
                                          onTap: () {
                                            Navigator.pop(ctx);
                                            _deleteScan(scan.id);
                                          },
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          tileColor: Colors.redAccent.withOpacity(0.1),
                                        ),
                                        const SizedBox(height: 10),
                                        ListTile(
                                          leading: Icon(Icons.cancel_outlined, color: Theme.of(context).textTheme.bodyLarge?.color?.withOpacity(0.7)),
                                          title: const Text('Cancel'),
                                          onTap: () => Navigator.pop(ctx),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                      ],
                                    ),
                                  )
                                );
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
          if (_isScanning)
            Positioned.fill(
              child: Container(
                color: Colors.black,
                child: _buildScannerView(),
              ),
            ),
        ],
      ),
      floatingActionButton: _isScanning ? null : FloatingActionButton.extended(
        onPressed: () {
          if (_isCameraPermissionGranted) {
             if (mounted) {
                _scannerController.start(); 
                setState(() {
                  _isScanning = true;
                  _scanSuccessful = false;
                  _scanFailed = false;
                  _scanFeedbackMessage = '';
                });
             }
          } else {
            _requestCameraPermission();
          }
        },
        tooltip: 'Scan QR Code',
        icon: const Icon(Icons.qr_code_scanner_rounded),
        label: const Text('Scan'),
        elevation: 4.0,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}