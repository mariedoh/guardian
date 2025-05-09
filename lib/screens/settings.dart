import 'package:flutter/material.dart';
import 'package:guardian/functions/emergency_shaker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'contacts_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // User preferences
  String _username = "User";
  String _videoRecordingDuration = "00:30"; // MM:SS
  String _timeLockDuration = "00:30"; // HH:MM
  int _safeDistance = 50; // in meters
  bool _emergencyMode = false;
  bool _isLoading = true;
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
        _username = prefs.getString('username') ?? "User";
        _videoRecordingDuration = prefs.getString('video_duration') ?? "00:30";
        _timeLockDuration = prefs.getString('time_lock') ?? "00:30";
        _safeDistance = prefs.getInt('safe_distance') ?? 50;
        _emergencyMode = prefs.getBool('emergency_mode') ?? false;
      });
    } catch (e) {
      // Handle error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load settings: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings(String key, dynamic value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      if (value is String) {
        await prefs.setString(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is bool) {
        await prefs.setBool(key, value);
        
        // If we're changing emergency mode, update the service
        if (key == 'emergency_mode') {
          await _emergencyService.setEmergencyMode(value);
        }
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save settings: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
          elevation: 1,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        elevation: 1,
      ),
      body: ListView(
        children: [
          // Personal Information Section
          _buildSectionHeader('Personal Information'),
          
          // Username
          _buildListTile(
            icon: Icons.person,
            title: 'Username',
            subtitle: _username,
            onTap: _editUsername,
          ),
          
          const Divider(),
          
          // Safety Features Section
          _buildSectionHeader('Safety Features'),
          
          // Emergency Contacts
          _buildListTile(
            icon: Icons.contacts,
            title: 'Emergency Contacts',
            subtitle: 'Add or modify your emergency contacts',
            onTap: _manageContacts,
          ),
          
          // Time-based Check-in Duration
          _buildListTile(
            icon: Icons.timer,
            title: 'Time-based Check-in Duration',
            subtitle: '$_timeLockDuration (HH:MM)',
            onTap: _editTimeLockDuration,
          ),
          
          // Video Recording Duration
          _buildListTile(
            icon: Icons.videocam,
            title: 'Video Recording Duration',
            subtitle: '$_videoRecordingDuration (MM:SS)',
            onTap: _editVideoRecordingDuration,
          ),
          
          // Safe Distance (Perimeter Lock)
          _buildListTile(
            icon: Icons.gps_fixed,
            title: 'Safe Distance (Perimeter Lock)',
            subtitle: '$_safeDistance meters',
            onTap: _editSafeDistance,
          ),
          
          const Divider(),
          
          // Emergency Mode Section
          _buildSectionHeader('Emergency Mode'),
          
          // Emergency Mode Toggle
          SwitchListTile(
            secondary: Icon(
              Icons.emergency,
              color: _emergencyMode ? Colors.red : null,
            ),
            title: const Text('Emergency Mode'),
            subtitle: Text(_emergencyMode 
                ? 'Active - Shake to record enabled' 
                : 'Inactive - Normal operation'),
            value: _emergencyMode,
            activeColor: Colors.red,
            onChanged: (bool value) {
              setState(() {
                _emergencyMode = value;
              });
              _saveSettings('emergency_mode', value);
              if (value) {
                _showEmergencyModeActivatedDialog();
              }
            },
          ),
          
          const Divider(),
          
          // App Information Section
          _buildSectionHeader('App Information'),
          
          // About
          _buildListTile(
            icon: Icons.info_outline,
            title: 'About Guardian Angel',
            subtitle: 'Version 1.0.0',
            onTap: _showAboutDialog,
          ),
          
          // Help
          _buildListTile(
            icon: Icons.help_outline,
            title: 'Help & Support',
            subtitle: 'Get help with Guardian Angel',
            onTap: _showHelpDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
        ),
      ),
    );
  }

  Widget _buildListTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  // Edit username
  Future<void> _editUsername() async {
    final controller = TextEditingController(text: _username);
    
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Username'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Username',
            hintText: 'Enter your preferred name',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                setState(() {
                  _username = controller.text;
                });
                _saveSettings('username', _username);
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // Edit time lock duration
  Future<void> _editTimeLockDuration() async {
    List<String> parts = _timeLockDuration.split(':');
    int hours = int.tryParse(parts[0]) ?? 0;
    int minutes = int.tryParse(parts[1]) ?? 30;
    
    TimeOfDay initialTime = TimeOfDay(hour: hours, minute: minutes);
    
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.blue,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (pickedTime != null) {
      String formattedHours = pickedTime.hour.toString().padLeft(2, '0');
      String formattedMinutes = pickedTime.minute.toString().padLeft(2, '0');
      String newDuration = '$formattedHours:$formattedMinutes';
      
      setState(() {
        _timeLockDuration = newDuration;
      });
      _saveSettings('time_lock', newDuration);
    }
  }

  // Edit video recording duration
  Future<void> _editVideoRecordingDuration() async {
    List<String> parts = _videoRecordingDuration.split(':');
    int minutes = int.tryParse(parts[0]) ?? 0;
    int seconds = int.tryParse(parts[1]) ?? 30;
    
    return showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Video Recording Duration'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Set the duration for emergency video recordings'),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Minutes
                    Column(
                      children: [
                        const Text('Minutes'),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: 60,
                          child: TextField(
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            controller: TextEditingController(text: minutes.toString()),
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (value) {
                              minutes = int.tryParse(value) ?? 0;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 20),
                    const Text(':', style: TextStyle(fontSize: 24)),
                    const SizedBox(width: 20),
                    // Seconds
                    Column(
                      children: [
                        const Text('Seconds'),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: 60,
                          child: TextField(
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            controller: TextEditingController(text: seconds.toString()),
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (value) {
                              seconds = int.tryParse(value) ?? 0;
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  // Validate input
                  if (seconds >= 60) {
                    minutes += seconds ~/ 60;
                    seconds %= 60;
                  }
                  
                  String formattedMinutes = minutes.toString().padLeft(2, '0');
                  String formattedSeconds = seconds.toString().padLeft(2, '0');
                  String newDuration = '$formattedMinutes:$formattedSeconds';
                  
                  this.setState(() {
                    _videoRecordingDuration = newDuration;
                  });
                  _saveSettings('video_duration', newDuration);
                  
                  Navigator.pop(context);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }


  // Edit safe distance
  Future<void> _editSafeDistance() async {
    final controller = TextEditingController(text: _safeDistance.toString());
    
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Safe Distance'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Set the safe distance for perimeter lock in meters'),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Distance (meters)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              int? value = int.tryParse(controller.text);
              if (value != null && value > 0) {
                setState(() {
                  _safeDistance = value;
                });
                _saveSettings('safe_distance', value);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a valid number')),
                );
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // Manage contacts
  void _manageContacts() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ContactsPage(),
      ),
    );
  }

  // Show help dialog
  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Help & Support'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Guardian Angel Features:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 10),
              Text('• Time-Based Check-In: Set a timer for your journey. If you don\'t check in by the end, your emergency contacts will be notified.'),
              SizedBox(height: 8),
              Text('• Emergency Mode: When activated, shake your phone to discreetly record video in dangerous situations.'),
              SizedBox(height: 8),
              Text('• Perimeter Lock: Set a safe zone. Get notified when someone leaves that area.'),
              SizedBox(height: 16),
              Text(
                'For more information or support:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('Email: support@guardianangel.com'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // Show about dialog
  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: 'Guardian Angel',
      applicationVersion: '1.0.0',
      applicationIcon: const Icon(
        Icons.shield,
        color: Colors.blue,
        size: 36,
      ),
      children: const [
        SizedBox(height: 10),
        Text('Guardian Angel is your personal safety companion, designed to help keep you and your loved ones safe.'),
        SizedBox(height: 10),
        Text('Features include Time-Based Check-In, Emergency Video Recording, and Perimeter Lock for location safety.'),
      ],
    );
  }

  // Show emergency mode activated dialog
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
  
  }