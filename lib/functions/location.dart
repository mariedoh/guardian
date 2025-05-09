import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

class LocationService {
  // Singleton pattern
  static final LocationService _instance = LocationService._internal();
  
  factory LocationService() {
    return _instance;
  }
  
  LocationService._internal();

  // Store the last known position
  Position? _lastKnownPosition;
  StreamSubscription<Position>? _positionStreamSubscription;
  bool _isTracking = false;

  /// Initialize the location service and request permissions
  Future<bool> initializeService() async {
    print('LocationService: Initializing service');
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print('LocationService: Location services are disabled');
      return false;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      print('LocationService: Location permissions denied, requesting permission');
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        print('LocationService: Location permissions denied');
        return false;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      print('LocationService: Location permissions permanently denied');
      return false;
    }

    print('LocationService: Service initialized successfully');
    return true;
  }

  /// Get the current location
  Future<Position?> getCurrentLocation() async {
    print('LocationService: Getting current location');
    try {
      final initialized = await initializeService();
      if (!initialized) {
        print('LocationService: Service not initialized');
        return null;
      }

      _lastKnownPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      print('LocationService: Current location obtained: ${_lastKnownPosition?.latitude}, ${_lastKnownPosition?.longitude}');
      return _lastKnownPosition;
    } catch (e) {
      print('LocationService: Error getting location: $e');
      return null;
    }
  }

  /// Start tracking location in the background
  Future<bool> startLocationTracking() async {
    print('LocationService: Starting location tracking');
    if (_isTracking) {
      print('LocationService: Already tracking');
      return true;
    }

    final initialized = await initializeService();
    if (!initialized) {
      print('LocationService: Service not initialized');
      return false;
    }

    try {
      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10, // Update if device moves 10 meters
        ),
      ).listen((Position position) {
        _lastKnownPosition = position;
        print('LocationService: Location updated: ${position.latitude}, ${position.longitude}');
        
        // Store the location in SharedPreferences for persistence
        _saveLastKnownLocation(position);
      });
      
      _isTracking = true;
      print('LocationService: Tracking started');
      return true;
    } catch (e) {
      print('LocationService: Error starting tracking: $e');
      return false;
    }
  }

  /// Stop tracking location
  void stopLocationTracking() {
    print('LocationService: Stopping location tracking');
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    _isTracking = false;
  }

  /// Save the last known location to SharedPreferences
  Future<void> _saveLastKnownLocation(Position position) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('last_known_lat', position.latitude);
      await prefs.setDouble('last_known_lng', position.longitude);
      await prefs.setDouble('last_known_accuracy', position.accuracy);
      await prefs.setDouble('last_known_altitude', position.altitude);
      await prefs.setDouble('last_known_speed', position.speed);
      await prefs.setDouble('last_known_heading', position.heading);
      await prefs.setInt('last_known_timestamp', position.timestamp?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch);
      
      print('LocationService: Saved last known location to SharedPreferences');
    } catch (e) {
      print('LocationService: Error saving location to SharedPreferences: $e');
    }
  }

  /// Load the last known location from SharedPreferences
  Future<Position?> loadLastKnownLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lat = prefs.getDouble('last_known_lat');
      final lng = prefs.getDouble('last_known_lng');
      
      if (lat == null || lng == null) {
        return null;
      }
      
      // Create a Position object from stored values
      _lastKnownPosition = Position(
        latitude: lat,
        longitude: lng,
        accuracy: prefs.getDouble('last_known_accuracy') ?? 0.0,
        altitude: prefs.getDouble('last_known_altitude') ?? 0.0,
        speed: prefs.getDouble('last_known_speed') ?? 0.0,
        heading: prefs.getDouble('last_known_heading') ?? 0.0,
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          prefs.getInt('last_known_timestamp') ?? DateTime.now().millisecondsSinceEpoch,
        ),
        speedAccuracy: 0.0,
        altitudeAccuracy: 0.0,
        headingAccuracy: 0.0,
      );
      
      print('LocationService: Loaded last known location from SharedPreferences');
      return _lastKnownPosition;
    } catch (e) {
      print('LocationService: Error loading location from SharedPreferences: $e');
      return null;
    }
  }

  /// Get the last known position (could be null if never tracked or got location)
  Future<Position?> getLastKnownPosition() async {
    if (_lastKnownPosition == null) {
      // Try to load from SharedPreferences if no position in memory
      return await loadLastKnownLocation();
    }
    return _lastKnownPosition;
  }

  /// Generate a Google Maps URL for the given position
  String generateMapsUrl(Position position) {
    return 'https://www.google.com/maps/search/?api=1&query=${position.latitude},${position.longitude}';
  }

  /// Get address from position
  Future<String> getAddressFromPosition(Position position) async {
    print('LocationService: Getting address for location: ${position.latitude}, ${position.longitude}');
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        final address = '${placemark.street}, ${placemark.locality}, ${placemark.postalCode}, ${placemark.country}';
        print('LocationService: Address obtained: $address');
        return address;
      } else {
        print('LocationService: No address found');
        return 'Unknown location';
      }
    } catch (e) {
      print('LocationService: Error getting address: $e');
      return 'Unknown location';
    }
  }

  /// Generate a complete location message
  Future<String> generateLocationMessage(String userName, {String reason = 'emergency'}) async {
    print('LocationService: Generating location message for $userName, reason: $reason');
    Position? position = await getLastKnownPosition();
    
    if (position == null) {
      position = await getCurrentLocation();
    }
    
    if (position == null) {
      print('LocationService: No location available for message');
      return '$userName may be in danger. Location unavailable.';
    }
    
    String address = await getAddressFromPosition(position);
    String mapsUrl = generateMapsUrl(position);
    
    String message;
    if (reason == 'perimeter_breach') {
      message = '$userName has moved outside the safe zone! Last known location: $address. View on map: $mapsUrl';
    } else {
      message = '$userName may be in danger. Last known location: $address. View on map: $mapsUrl';
    }
    
    print('LocationService: Message generated: $message');
    return message;
  }
}