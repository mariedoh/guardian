import 'package:flutter/material.dart';
import 'package:flutter_background_video_recorder/flutter_bvr_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:flutter_background_video_recorder/flutter_bvr.dart';
import 'package:shake/shake.dart';

class EmergencyService {
  static final EmergencyService _instance = EmergencyService._internal();
  factory EmergencyService() => _instance;
  EmergencyService._internal();

  bool _isRecording = false;
  bool _recorderBusy = false;
  bool _emergencyModeActive = false;
  bool _isInitialized = false;
  StreamSubscription<int?>? _streamSubscription;
  final _flutterBackgroundVideoRecorderPlugin = FlutterBackgroundVideoRecorder();
  ShakeDetector? _detector;

  // Initialize the emergency service with better error handling
  Future<void> init() async {
    try {
      debugPrint('🔍 EmergencyService init starting...');
      
      // First load preferences
      await _loadEmergencyModeState();
      
      // Try to initialize the recorder plugin
      bool recorderInitialized = await _initializeRecorder();
      debugPrint('📹 Recorder initialized: $recorderInitialized');
      
      // Only start shake detection if recorder is initialized and emergency mode is active
      if (_emergencyModeActive) {
        debugPrint('🚨 Emergency mode active, starting shake detection');
        // Add a delay before starting shake detection to ensure everything is ready
        await Future.delayed(Duration(milliseconds: 500));
        startShakeDetection();
      } else {
        debugPrint('ℹ️ Emergency mode not active, skipping shake detection');
      }
      
      _isInitialized = true;
      debugPrint('✅ EmergencyService init completed successfully');
    } catch (e) {
      debugPrint('❌ Error in EmergencyService.init(): $e');
      _isInitialized = false;
    }
  }

  // Separate method for initializing recorder
  Future<bool> _initializeRecorder() async {
    try {
      // Get initial recording status
      await getInitialRecordingStatus();
      
      // Wait a bit longer to ensure plugin is fully initialized
      await Future.delayed(Duration(milliseconds: 500));
      
      // Now listen to recorder state
      listenRecordingState();
      return true;
    } catch (e) {
      debugPrint('❌ Error initializing recorder: $e');
      return false;
    }
  }

  // Load emergency mode state from shared preferences
  Future<void> _loadEmergencyModeState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _emergencyModeActive = prefs.getBool('emergency_mode') ?? false;
      debugPrint('🔄 Loaded emergency mode state: $_emergencyModeActive');
    } catch (e) {
      debugPrint('❌ Error loading emergency mode state: $e');
      _emergencyModeActive = false;
    }
  }

  // Get initial recording status with improved error handling
  Future<void> getInitialRecordingStatus() async {
    try {
      final status = await _flutterBackgroundVideoRecorderPlugin.getVideoRecordingStatus();
      _isRecording = status == 1;
      debugPrint('📊 Got initial recording status: $_isRecording');
    } catch (e) {
      debugPrint('❌ Error getting recording status: $e');
      _isRecording = false;
    }
  }

  // Listen to recorder state changes with improved error handling
  void listenRecordingState() {
    try {
      // Cancel any existing subscription first
      _streamSubscription?.cancel();
      _streamSubscription = null;
      
      debugPrint('👂 Setting up recorder state listener...');
      
      // Start with clean state
      _isRecording = false;
      _recorderBusy = false;
      
      // Wrap in try-catch specifically for the listen method
      try {
        _streamSubscription = 
            _flutterBackgroundVideoRecorderPlugin.recorderState.listen((event) {
          debugPrint('🔄 Recorder state changed: $event');
          switch (event) {
            case 1:
              _isRecording = true;
              _recorderBusy = true;
              debugPrint('📹 Recording STARTED');
              break;
            case 2:
              _isRecording = false;
              _recorderBusy = false;
              debugPrint('📹 Recording STOPPED');
              break;
            case 3:
              _recorderBusy = true;
              debugPrint('📹 Recorder BUSY');
              break;
            case -1:
              _isRecording = false;
              debugPrint('📹 Recording ERROR');
              break;
            default:
              debugPrint('📹 Unknown recorder state: $event');
              return;
          }
        }, onError: (error) {
          debugPrint('❌ Error in recorder state stream: $error');
        });
        debugPrint('✅ Recorder state listener set up successfully');
      } catch (e) {
        debugPrint('❌ Error specifically in .listen() call: $e');
        // Set safe default states
        _isRecording = false;
        _recorderBusy = false;
      }
    } catch (e) {
      debugPrint('❌ Error setting up recorder state listener: $e');
      // Set safe default states
      _isRecording = false;
      _recorderBusy = false;
    }
  }

  // Start shake detection with improved error handling
  void startShakeDetection() {
    if (_detector != null) {
      stopShakeDetection();
    }
    
    try {
      // Modified shake sensitivity to be more like the working version
      double _shakeThreshold = 2.7; // Same as in working shake.dart
      bool _useFilter = false;
      int _minimumShakeCount = 1;

      debugPrint('🤝 Starting shake detection...');
      
      _detector = ShakeDetector.autoStart(
        onPhoneShake: _handleShakeEvent,
        minimumShakeCount: _minimumShakeCount,
        shakeSlopTimeMS: 500,
        shakeCountResetTime: 3000,
        shakeThresholdGravity: _shakeThreshold,
        useFilter: _useFilter,
      );
      
      debugPrint('✅ Shake detection started successfully');
    } catch (e) {
      debugPrint('❌ Error starting shake detection: $e');
    }
  }
  
  // Separate method to handle shake events - helps with debugging
  void _handleShakeEvent(ShakeEvent event) {
    debugPrint('📱 Shake detected! Current recording state: $_isRecording, busy: $_recorderBusy');
    
    // Force check current recording status before proceeding
    try {
      _flutterBackgroundVideoRecorderPlugin.getVideoRecordingStatus().then((status) {
        _isRecording = status == 1;
        debugPrint('📊 Refreshed recording status: $_isRecording');
        
        if (!_isRecording && !_recorderBusy) {
          debugPrint('🚀 Starting recording from shake event handler');
          startRecording("Rear camera");
        } else {
          debugPrint('⏸️ Ignoring shake - already recording: $_isRecording, recorder busy: $_recorderBusy');
        }
      }).catchError((error) {
        debugPrint('❌ Error refreshing recording status: $error');
        // Proceed anyway assuming not recording
        if (!_recorderBusy) {
          debugPrint('🚀 Starting recording despite status refresh error');
          startRecording("Rear camera");
        }
      });
    } catch (e) {
      debugPrint('❌ Error in shake event handler: $e');
      // Last resort - try to record anyway
      if (!_recorderBusy) {
        debugPrint('🚀 Attempting recording despite error');
        startRecording("Rear camera");
      }
    }
  }

  // Start video recording with improved error handling and simplified approach
  Future<void> startRecording(String cameraFacing) async {
    if (_isRecording) {
      debugPrint('⚠️ Already recording, will not start another recording');
      return;
    }
    
    if (_recorderBusy) {
      debugPrint('⚠️ Recorder busy, waiting 1 second before retry');
      await Future.delayed(Duration(seconds: 1));
      if (_recorderBusy) {
        debugPrint('⚠️ Recorder still busy after delay, aborting');
        return;
      }
    }

    try {
      // Use simpler duration logic like in the working version
      int minutes = 0;
      int seconds = 30; // Default to 30 seconds like in working version
      
      // Try to get custom duration from preferences
      try {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        // Check both keys that might contain duration (film_duration from working example, video_duration from yours)
        String timing = prefs.getString("film_duration") ?? prefs.getString("video_duration") ?? "";
        
        if (timing.isNotEmpty) {
          List<String> parts = timing.split(":");
          if (parts.length == 2) {
            minutes = int.tryParse(parts[0]) ?? 0;
            seconds = int.tryParse(parts[1]) ?? 30;
          }
        }
      } catch (e) {
        debugPrint('⚠️ Error getting duration preferences: $e');
        // Continue with defaults
      }

      debugPrint('🎬 Starting video recording for $minutes minutes and $seconds seconds');
      
      // Set flags before actual recording to prevent race conditions
      _recorderBusy = true;

      await _flutterBackgroundVideoRecorderPlugin.startVideoRecording(
        folderName: "Guardian Angel Recordings",
        cameraFacing: cameraFacing == "Rear camera"
            ? CameraFacing.rearCamera
            : CameraFacing.frontCamera,
        notificationTitle: "Guardian Angel",
        notificationText: "Recording in progress...",
        showToast: false,
      );
      
      debugPrint('✅ Recording started successfully');
      
      // Stop recording after the configured duration
      Timer(Duration(minutes: minutes, seconds: seconds), () async {
        debugPrint('⏱️ Timer triggered, stopping recording');
        await stopRecording();
      });
    } catch (e) {
      debugPrint('❌ Error starting recording: $e');
      // Reset flags on error
      _recorderBusy = false;
      _isRecording = false;
    }
  }

  // Stop recording with improved error handling
  Future<void> stopRecording() async {
    try {
      debugPrint('⏹️ Attempting to stop video recording');
      await _flutterBackgroundVideoRecorderPlugin.stopVideoRecording();
      debugPrint('✅ Recording stopped successfully');
    } catch (e) {
      debugPrint('❌ Error stopping recording: $e');
      // Force reset state if error
      _isRecording = false;
      _recorderBusy = false;
    }
  }

  // Set emergency mode state with improved state management
  Future<void> setEmergencyMode(bool value) async {
    try {
      _emergencyModeActive = value;
      debugPrint('🔄 Setting emergency mode to: $value');
      
      // Save the state to shared preferences first
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('emergency_mode', value);
      
      // Now handle the actual mode change
      if (value) {
        debugPrint('🚨 Emergency mode activated, starting shake detection');
        // Re-initialize recorder to ensure clean state 
        await _initializeRecorder();
        await Future.delayed(Duration(milliseconds: 500));
        startShakeDetection();
      } else {
        debugPrint('🔄 Emergency mode deactivated, stopping shake detection');
        stopShakeDetection();
      }
      
      debugPrint('✅ Emergency mode ${value ? 'activated' : 'deactivated'} successfully');
    } catch (e) {
      debugPrint('❌ Error setting emergency mode: $e');
    }
  }

  // Stop shake detection with improved error handling
  void stopShakeDetection() {
    try {
      if (_detector != null) {
        _detector?.stopListening();
        _detector = null;
        debugPrint('✅ Shake detection stopped');
      }
    } catch (e) {
      debugPrint('❌ Error stopping shake detection: $e');
      _detector = null;
    }
  }

  // Dispose resources properly
  void dispose() {
    try {
      _streamSubscription?.cancel();
      stopShakeDetection();
      debugPrint('✅ EmergencyService disposed');
    } catch (e) {
      debugPrint('❌ Error disposing EmergencyService: $e');
    }
  }

  // Check if emergency mode is active
  bool get isEmergencyModeActive => _emergencyModeActive;
  
  // Check if service is initialized
  bool get isInitialized => _isInitialized;
}