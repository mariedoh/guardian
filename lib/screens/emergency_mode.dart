import 'package:flutter/material.dart';
import 'package:guardian/functions/emergency_shaker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

class EmergencyModePage extends StatefulWidget {
  const EmergencyModePage({Key? key}) : super(key: key);

  @override
  _EmergencyModePageState createState() => _EmergencyModePageState();
}

class _EmergencyModePageState extends State<EmergencyModePage> {
  bool _emergencyMode = false;
  bool _isLoading = true;
  String _videoRecordingDuration = "00:30"; // Default duration
  final EmergencyService _emergencyService = EmergencyService();
  
  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _emergencyMode = prefs.getBool('emergency_mode') ?? false;
        _videoRecordingDuration = prefs.getString('video_duration') ?? "00:30";
        _isLoading = false;
      });
    } catch (e) {
      // Handle error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load settings: $e')),
      );
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleEmergencyMode(bool value) async {
    if (value) {
      // Check and request permissions when enabling
      bool permissionsGranted = await _checkAndRequestPermissions();
      if (!permissionsGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera and storage permissions are required for Emergency Mode'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
    }

    // Show loading indicator
    setState(() {
      _isLoading = true;
    });

    try {
      // Update SharedPreferences first
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('emergency_mode', value);
      
      // Then update the emergency service
      await _emergencyService.setEmergencyMode(value);
      
      setState(() {
        _emergencyMode = value;
        _isLoading = false;
      });
      
      if (value) {
        _showEmergencyModeActivatedDialog();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update emergency mode: $e')),
      );
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<bool> _checkAndRequestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.storage,
      Permission.microphone,
    ].request();
    
    return statuses[Permission.camera]!.isGranted && 
           statuses[Permission.storage]!.isGranted &&
           statuses[Permission.microphone]!.isGranted;
  }

  void _showEmergencyModeActivatedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Emergency Mode Activated'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Emergency Mode is now active. You can shake your device to discreetly start recording video even when the app is in the background.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 15),
            Text(
              'Video will record for $_videoRecordingDuration (MM:SS)',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              'Note: Make sure to grant camera and storage permissions for this feature to work properly.',
              style: TextStyle(fontSize: 14, color: Colors.red),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Emergency Mode'),
          backgroundColor: _emergencyMode ? Colors.red : null,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Mode'),
        backgroundColor: _emergencyMode ? Colors.red : null,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Emergency Mode Status
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.emergency,
                        color: _emergencyMode ? Colors.red : Colors.grey,
                        size: 36,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Emergency Mode',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: _emergencyMode ? Colors.red : null,
                              ),
                            ),
                            Text(
                              _emergencyMode
                                  ? 'Active - Shake to record enabled'
                                  : 'Inactive - Normal operation',
                              style: TextStyle(
                                color: _emergencyMode ? Colors.red : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _emergencyMode,
                        activeColor: Colors.red,
                        onChanged: _toggleEmergencyMode,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // How To Use Section
          const Text(
            'How To Use',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          const Card(
            elevation: 2,
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '1. Activate Emergency Mode',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Toggle the switch above to enable Emergency Mode.',
                  ),
                  SizedBox(height: 12),
                  Text(
                    '2. Shake to Record',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'When in danger, simply shake your phone to discreetly start recording video.',
                  ),
                  SizedBox(height: 12),
                  Text(
                    '3. Automatic Recording',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'The app will automatically record for the duration set in your settings.',
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Important Notes Section
          const Text(
            'Important Notes',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          const Card(
            elevation: 2,
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    leading: Icon(Icons.battery_alert, color: Colors.orange),
                    title: Text('Battery Usage'),
                    subtitle: Text('Emergency mode may use more battery when active'),
                    contentPadding: EdgeInsets.all(0),
                  ),
                  ListTile(
                    leading: Icon(Icons.perm_camera_mic, color: Colors.blue),
                    title: Text('Permissions Required'),
                    subtitle: Text('Camera and storage permissions must be granted'),
                    contentPadding: EdgeInsets.all(0),
                  ),
                  ListTile(
                    leading: Icon(Icons.videocam, color: Colors.green),
                    title: Text('Video Storage'),
                    subtitle: Text('Videos are saved in the Guardian Angel Recordings folder'),
                    contentPadding: EdgeInsets.all(0),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Test Button
          // ElevatedButton(
          //   onPressed: () async {
          //     if (_emergencyMode) {
          //       bool permissionsGranted = await _checkAndRequestPermissions();
          //       if (!permissionsGranted) {
          //         ScaffoldMessenger.of(context).showSnackBar(
          //           const SnackBar(
          //             content: Text('Camera and storage permissions are required for test recording'),
          //             duration: Duration(seconds: 3),
          //           ),
          //         );
          //         return;
          //       }
                
          //       _emergencyService.startRecording("Rear camera");
          //       ScaffoldMessenger.of(context).showSnackBar(
          //         const SnackBar(
          //           content: Text('Test recording started. It will stop automatically after the set duration.'),
          //           duration: Duration(seconds: 5),
          //         ),
          //       );
          //     } else {
          //       ScaffoldMessenger.of(context).showSnackBar(
          //         const SnackBar(
          //           content: Text('Please enable Emergency Mode first to test recording.'),
          //           duration: Duration(seconds: 3),
          //         ),
          //       );
          //     }
          //   },
          //   style: ElevatedButton.styleFrom(
          //     backgroundColor: Colors.blue,
          //     padding: const EdgeInsets.symmetric(vertical: 16),
          //   ),
          //   child: const Text(
          //     'TEST RECORDING',
          //     style: TextStyle(
          //       fontSize: 16,
          //       fontWeight: FontWeight.bold,
          //     ),
          //   ),
          // ),
        ],
      ),
    );
  }
}