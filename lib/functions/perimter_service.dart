// File: perimeter_service.dart (renamed from perimter_service.dart)
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:guardian/functions/messenger.dart';
import 'package:guardian/functions/location.dart';

class PerimeterService {
  // Singleton pattern
  static final PerimeterService _instance = PerimeterService._internal();
  
  factory PerimeterService() {
    return _instance;
  }
  
  PerimeterService._internal();

  // Core properties
  final LocationService _locationService = LocationService();
  StreamSubscription<Position>? _locationSubscription;
  double _centerLat = 0;
  double _centerLng = 0;
  int _safeDistance = 50;
  bool _isMonitoring = false;
  bool _hasAlerted = false;
  final MessageService _messageService = MessageService();
  
  // Used to track whether we're inside or outside the perimeter
  bool _isOutsidePerimeter = false;
  
  // Timer to handle alert cooldown
  Timer? _alertCooldownTimer;
  static const int ALERT_COOLDOWN_MINUTES = 5; // Only send another alert after 5 minutes

  // Initialize location service
  Future<bool> initialize() async {
    try {
      // Request permissions through LocationService
      bool initialized = await _locationService.initializeService();
      if (!initialized) {
        print('PerimeterService: Location services initialization failed');
        return false;
      }

      // Initialize message service and its permissions
      await _messageService.initializeAndRequestPermissions();

      print('PerimeterService: Initialization successful');
      return true;
    } catch (e) {
      print('PerimeterService: Initialization error: $e');
      return false;
    }
  }

  // Get current location
  Future<Position?> getCurrentLocation() async {
    try {
      await initialize();
      final position = await _locationService.getCurrentLocation();
      if (position != null) {
        print('PerimeterService: Current location: ${position.latitude}, ${position.longitude}');
      }
      return position;
    } catch (e) {
      print('PerimeterService: Error getting current location: $e');
      return null;
    }
  }

  // Start monitoring location
  Future<bool> startMonitoring(double centerLat, double centerLng, int safeDistance) async {
    // Cancel any existing subscription
    await stopMonitoring();
    
    try {
      print('PerimeterService: Starting monitoring');
      bool initialized = await initialize();
      if (!initialized) {
        print('PerimeterService: Failed to initialize');
        return false;
      }

      // Verify that we have emergency contacts configured
      bool hasContacts = await _messageService.hasEmergencyContacts();
      if (!hasContacts) {
        print('PerimeterService: No emergency contacts configured');
        return false;
      }

      // Save parameters
      _centerLat = centerLat;
      _centerLng = centerLng;
      _safeDistance = safeDistance;
      _hasAlerted = false;
      _isOutsidePerimeter = false; // Reset state
      
      // Start location tracking in LocationService first
      await _locationService.startLocationTracking();
      
      // Begin location subscription with higher frequency updates
      _locationSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 1, // Update more frequently - every 5 meters
        ),
      ).listen(
        (Position position) {
          _checkLocation(position);
        },
        onError: (e) {
          print('PerimeterService: Location subscription error: $e');
        },
      );
      
      // Update shared preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('perimeter_active', true);
      await prefs.setInt('safe_distance', safeDistance);
      await prefs.setDouble('perimeter_center_lat', centerLat);
      await prefs.setDouble('perimeter_center_lng', centerLng);
      
      _isMonitoring = true;
      print('PerimeterService: Monitoring started at center: $_centerLat, $_centerLng with safe distance: $_safeDistance meters');
      return true;
    } catch (e) {
      print('PerimeterService: Error starting monitoring: $e');
      return false;
    }
  }

  // Stop monitoring location
  Future<bool> stopMonitoring() async {
    try {
      if (_locationSubscription != null) {
        await _locationSubscription!.cancel();
        _locationSubscription = null;
      }
      
      // Cancel any running timers
      _alertCooldownTimer?.cancel();
      _alertCooldownTimer = null;
      
      // Update shared preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('perimeter_active', false);
      
      _isMonitoring = false;
      _hasAlerted = false;
      _isOutsidePerimeter = false;
      print('PerimeterService: Monitoring stopped');
      return true;
    } catch (e) {
      print('PerimeterService: Error stopping monitoring: $e');
      return false;
    }
  }

  // Check if the location is outside the safe zone
  void _checkLocation(Position position) {
    if (!_isMonitoring) {
      return;
    }

    double distance = _calculateDistance(
      _centerLat, 
      _centerLng, 
      position.latitude, 
      position.longitude
    );
    
    print('PerimeterService: Current distance from center: $distance meters (safe distance: $_safeDistance meters)');
    
    bool isCurrentlyOutside = distance > _safeDistance;
    
    // If we've moved from inside to outside, send alert
    if (isCurrentlyOutside && !_isOutsidePerimeter) {
      print('PerimeterService: Just crossed outside safe zone! Distance: $distance meters');
      _sendAlert(position);
    } 
    // If we've moved from outside to inside, reset alert status
    else if (!isCurrentlyOutside && _isOutsidePerimeter) {
      print('PerimeterService: Returned to safe zone');
      resetAlertStatus();
    }
    
    // Update state
    _isOutsidePerimeter = isCurrentlyOutside;
  }

  // Calculate distance between two points using Haversine formula
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // Earth radius in meters
    
    // Convert degrees to radians
    double lat1Rad = lat1 * pi / 180;
    double lon1Rad = lon1 * pi / 180;
    double lat2Rad = lat2 * pi / 180;
    double lon2Rad = lon2 * pi / 180;
    
    // Differences
    double dLat = lat2Rad - lat1Rad;
    double dLon = lon2Rad - lon1Rad;
    
    // Haversine formula
    double a = sin(dLat / 2) * sin(dLat / 2) +
               cos(lat1Rad) * cos(lat2Rad) * 
               sin(dLon / 2) * sin(dLon / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    double distance = earthRadius * c;
    
    return distance;
  }

  // Send alert to emergency contacts
  Future<void> _sendAlert(Position position) async {
    if (_hasAlerted && _alertCooldownTimer != null) {
      print('PerimeterService: Alert already sent and in cooldown period');
      return; // Don't send another alert during cooldown
    }
    
    try {
      _hasAlerted = true;
      print('PerimeterService: Sending perimeter breach alert');
      
      // Use the specific perimeter breach alert method
      bool hasSent = await _messageService.sendPerimeterBreachAlert();
      
      if (hasSent) {
        print('PerimeterService: Alert sent successfully');
        
        // Save the alert to shared preferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('last_alert_perimeter_breach', true);
        await prefs.setInt('last_alert_timestamp', DateTime.now().millisecondsSinceEpoch);
        await prefs.setDouble('last_alert_lat', position.latitude);
        await prefs.setDouble('last_alert_lng', position.longitude);
        
        // Set a cooldown timer so we don't spam alerts
        _alertCooldownTimer = Timer(Duration(minutes: ALERT_COOLDOWN_MINUTES), () {
          print('PerimeterService: Alert cooldown period ended');
          _hasAlerted = false; // Allow sending alerts again
          _alertCooldownTimer = null;
        });
        
      } else {
        print('PerimeterService: Failed to send alert');
        _hasAlerted = false; // Reset flag to try again
      }
    } catch (e) {
      print('PerimeterService: Error sending alert: $e');
      _hasAlerted = false; // Reset flag to try again
    }
  }

  // Check if monitoring is active
  bool isMonitoring() {
    return _isMonitoring;
  }
  
  // Get current safe distance setting
  Future<int> getSafeDistance() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('safe_distance') ?? 50;
  }
  
  // Set safe distance
  Future<bool> setSafeDistance(int meters) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('safe_distance', meters);
      
      _safeDistance = meters;
      
      // If monitoring is active, update with new distance
      if (_isMonitoring) {
        print('PerimeterService: Updating safe distance to $meters meters');
        
        // Restart monitoring with new parameters
        return await startMonitoring(_centerLat, _centerLng, meters);
      }
      
      return true;
    } catch (e) {
      print('PerimeterService: Error setting safe distance: $e');
      return false;
    }
  }
  
  // Reset alert status
  void resetAlertStatus() {
    print('PerimeterService: Resetting alert status');
    _hasAlerted = false;
    _alertCooldownTimer?.cancel();
    _alertCooldownTimer = null;
  }
}