import 'package:flutter/material.dart';
import 'package:guardian/functions/location.dart' show LocationService;
import 'package:guardian/functions/messenger.dart' show MessageService;
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class TimeBasedCheckInPage extends StatefulWidget {
  const TimeBasedCheckInPage({Key? key}) : super(key: key);

  @override
  _TimeBasedCheckInPageState createState() => _TimeBasedCheckInPageState();
}

class _TimeBasedCheckInPageState extends State<TimeBasedCheckInPage> {
  bool _isTimerActive = false;
  bool _isLoading = true;
  String _timeLockDuration = "00:30"; // HH:MM format from settings
  DateTime? _endTime;
  Timer? _countdownTimer;
  String _remainingTime = "";
  List<dynamic> _emergencyContacts = [];
  LocationService _locationService = LocationService();
  MessageService _messageService = MessageService();
  bool _isLocationTrackingActive = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _initializeLocationService();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    if (_isLocationTrackingActive) {
      _locationService.stopLocationTracking();
    }
    super.dispose();
  }

  Future<void> _initializeLocationService() async {
    print('TimeBasedCheckIn: Initializing location service');
    bool initialized = await _locationService.initializeService();
    if (initialized) {
      print('TimeBasedCheckIn: Location service initialized successfully');
    } else {
      print('TimeBasedCheckIn: Failed to initialize location service');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location services not available. Some features may not work properly.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load time lock duration
      String timeLock = prefs.getString('time_lock') ?? "00:30";
      
      // Load active timer if exists
      bool isActive = prefs.getBool('timer_active') ?? false;
      String? endTimeString = prefs.getString('timer_end_time');
      DateTime? endTime;
      
      if (endTimeString != null) {
        endTime = DateTime.tryParse(endTimeString);
      }
      
      // Load emergency contacts
      String? contactsJson = prefs.getString('emergency_contacts');
      List<dynamic> contacts = [];
      
      if (contactsJson != null) {
        contacts = jsonDecode(contactsJson);
      }

      setState(() {
        _timeLockDuration = timeLock;
        _isTimerActive = isActive && endTime != null && endTime.isAfter(DateTime.now());
        _endTime = endTime;
        _emergencyContacts = contacts;
        _isLoading = false;
      });
      
      if (_isTimerActive && _endTime != null) {
        _startCountdown();
        // Start location tracking when timer is active
        _startLocationTracking();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load settings: $e')),
      );
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _startLocationTracking() async {
    if (!_isLocationTrackingActive) {
      print('TimeBasedCheckIn: Starting location tracking');
      bool started = await _locationService.startLocationTracking();
      if (started) {
        _isLocationTrackingActive = true;
        print('TimeBasedCheckIn: Location tracking started');
      } else {
        print('TimeBasedCheckIn: Failed to start location tracking');
      }
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_endTime == null) {
        timer.cancel();
        return;
      }
      
      final now = DateTime.now();
      if (_endTime!.isBefore(now)) {
        // Timer has expired
        _handleTimerExpired();
        timer.cancel();
        return;
      }
      
      final remaining = _endTime!.difference(now);
      final hours = remaining.inHours;
      final minutes = remaining.inMinutes % 60;
      final seconds = remaining.inSeconds % 60;
      
      setState(() {
        _remainingTime = '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
      });
    });
  }

  Future<void> _startTimer() async {
    // Parse duration
    List<String> parts = _timeLockDuration.split(':');
    int hours = int.tryParse(parts[0]) ?? 0;
    int minutes = int.tryParse(parts[1]) ?? 30;
    
    // Calculate end time
    DateTime endTime = DateTime.now().add(Duration(hours: hours, minutes: minutes));
    
    // Save to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('timer_active', true);
    await prefs.setString('timer_end_time', endTime.toIso8601String());
    
    setState(() {
      _isTimerActive = true;
      _endTime = endTime;
    });
    
    // Start countdown
    _startCountdown();
    
    // Start location tracking
    await _startLocationTracking();
    
    // Show confirmation
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Check-in timer started for $_timeLockDuration'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _cancelTimer() async {
    // Confirm cancellation
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Check-In Confirmation'),
        content: const Text('Are you safe and wish to cancel the timer?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, I am safe'),
          ),
        ],
      ),
    ) ?? false;
    
    if (!confirm) return;
    
    // Save to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('timer_active', false);
    await prefs.remove('timer_end_time');
    
    // Update state
    setState(() {
      _isTimerActive = false;
      _endTime = null;
    });
    
    // Cancel countdown
    _countdownTimer?.cancel();
    
    // Stop location tracking
    if (_isLocationTrackingActive) {
      _locationService.stopLocationTracking();
      _isLocationTrackingActive = false;
      print('TimeBasedCheckIn: Location tracking stopped');
    }
    
    // Show confirmation
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Check-in timer cancelled successfully'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _handleTimerExpired() async {
    print('TimeBasedCheckIn: Timer expired, handling emergency protocol');
    
    // Update state
    setState(() {
      _isTimerActive = false;
      _remainingTime = "EXPIRED";
    });
    
    // Save to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('timer_active', false);
    await prefs.remove('timer_end_time');
    
    // Check if we have contacts to notify
    bool hasContacts = await _messageService.hasEmergencyContacts();
    if (!hasContacts) {
      print('TimeBasedCheckIn: No emergency contacts to notify');
      _showNoContactsDialog();
      return;
    }
    
    // Send emergency SMS
    print('TimeBasedCheckIn: Sending emergency SMS');
    bool sentSuccessfully = await _messageService.sendEmergencySMS();
    
    if (sentSuccessfully) {
      print('TimeBasedCheckIn: Emergency SMS sent successfully');
    } else {
      print('TimeBasedCheckIn: Failed to send emergency SMS');
    }
    
    // Show notification dialog
    _showEmergencyNotificationSent();
    
    // Stop location tracking after sending emergency message
    if (_isLocationTrackingActive) {
      _locationService.stopLocationTracking();
      _isLocationTrackingActive = false;
      print('TimeBasedCheckIn: Location tracking stopped after emergency');
    }
  }
  
  void _showEmergencyNotificationSent() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Emergency Notification Sent', style: TextStyle(color: Colors.red)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Your timer has expired and we have notified your emergency contacts with your location details.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              '${_emergencyContacts.length} contact(s) notified',
              style: const TextStyle(fontWeight: FontWeight.bold),
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
  
  void _showNoContactsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('No Emergency Contacts'),
        content: const Text(
          'You have no emergency contacts set up. Please add contacts in the Settings page for the Time-Based Check-In feature to work properly.',
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

  void _showTimerInfoDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Time-Based Check-In'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How it works:'),
            SizedBox(height: 12),
            Text('1. Set a timer for your journey or activity'),
            SizedBox(height: 8),
            Text('2. If you don\'t check in before the timer expires, your emergency contacts will be automatically notified with your location'),
            SizedBox(height: 8),
            Text('3. You can check in at any time by pressing the "I\'m Safe" button'),
            SizedBox(height: 12),
            Text(
              'Note: Make sure you have added emergency contacts in Settings for this feature to work properly.',
              style: TextStyle(fontStyle: FontStyle.italic, color: Colors.red),
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

  void _editTimerDuration() async {
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
      
      // Save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('time_lock', newDuration);
      
      setState(() {
        _timeLockDuration = newDuration;
      });
      
      // Show confirmation
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Timer duration updated to $_timeLockDuration')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Time-Based Check-In'),
          backgroundColor: _isTimerActive ? Colors.orange : null,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Time-Based Check-In'),
        backgroundColor: _isTimerActive ? Colors.orange : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showTimerInfoDialog,
            tooltip: 'How it works',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Timer Status Card
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
                        Icons.timer,
                        color: _isTimerActive ? Colors.orange : Colors.grey,
                        size: 36,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Safety Timer',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: _isTimerActive ? Colors.orange : null,
                              ),
                            ),
                            Text(
                              _isTimerActive
                                  ? 'Active - Please check in before time expires'
                                  : 'Inactive - Start timer for your journey',
                              style: TextStyle(
                                color: _isTimerActive ? Colors.orange : Colors.grey,
                              ),
                            ),
                            if (_isTimerActive && _isLocationTrackingActive)
                              const Text(
                                'Location tracking enabled',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.green,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_isTimerActive) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Time Remaining:',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _remainingTime,
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _cancelTimer,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle),
                          SizedBox(width: 8),
                          Text(
                            "I'M SAFE - CHECK IN NOW",
                            style: TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Timer Duration: $_timeLockDuration',
                          style: const TextStyle(fontSize: 16),
                        ),
                        TextButton.icon(
                          onPressed: _editTimerDuration,
                          icon: const Icon(Icons.edit, size: 16),
                          label: const Text('Edit'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _startTimer,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                      ),
                      child: const Text(
                        'START TIMER',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
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
                    '1. Set Timer',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Start a timer when beginning your journey or activity.',
                  ),
                  SizedBox(height: 12),
                  Text(
                    '2. Check In',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'When you\'re safe, press the "I\'M SAFE" button to cancel the timer.',
                  ),
                  SizedBox(height: 12),
                  Text(
                    '3. Automatic Alerts',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'If the timer expires, your emergency contacts will be automatically notified with your location.',
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
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ListTile(
                    leading: Icon(Icons.contacts, color: Colors.blue),
                    title: Text('Emergency Contacts Required'),
                    subtitle: Text('Add contacts in Settings for automatic notifications'),
                    contentPadding: EdgeInsets.all(0),
                  ),
                  const ListTile(
                    leading: Icon(Icons.location_on, color: Colors.red),
                    title: Text('Location Tracking'),
                    subtitle: Text('Your location is only tracked during active timers'),
                    contentPadding: EdgeInsets.all(0),
                  ),
                  const ListTile(
                    leading: Icon(Icons.battery_alert, color: Colors.orange),
                    title: Text('Keep Your Phone Charged'),
                    subtitle: Text('Ensure your device has enough battery for the duration'),
                    contentPadding: EdgeInsets.all(0),
                  ),
                  ListTile(
                    leading: const Icon(Icons.alarm, color: Colors.green),
                    title: const Text('Default Timer Duration'),
                    subtitle: Text('Current setting: $_timeLockDuration (HH:MM)'),
                    contentPadding: const EdgeInsets.all(0),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Emergency Contacts Status
          Card(
            elevation: 2,
            color: _emergencyContacts.isEmpty ? Colors.red.shade50 : Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.people,
                        color: _emergencyContacts.isEmpty ? Colors.red : Colors.green,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Emergency Contacts',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _emergencyContacts.isEmpty ? Colors.red : Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _emergencyContacts.isEmpty
                        ? 'No emergency contacts added. Please add contacts in Settings.'
                        : '${_emergencyContacts.length} emergency contact(s) will be notified if timer expires.',
                    style: TextStyle(
                      color: _emergencyContacts.isEmpty ? Colors.red.shade700 : Colors.green.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}