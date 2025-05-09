// File: messenger.dart
import 'package:flutter/material.dart';
import 'package:sms_mms/sms_mms.dart';
import 'package:another_telephony/telephony.dart';
import 'package:guardian/functions/location.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';

class MessageService {
  // Singleton pattern
  static final MessageService _instance = MessageService._internal();
  final Telephony telephony = Telephony.instance;
  bool _initialized = false;
  
  factory MessageService() {
    return _instance;
  }
  
  MessageService._internal();

  /// Load the user's name from shared preferences
  Future<String> _getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    // Changed from 'user_name' to 'username' to match settings.dart
    return prefs.getString('username') ?? 'User';
  }

  /// Load emergency contacts from shared preferences
  Future<List<String>> _getEmergencyContactNumbers() async {
    print('MessageService: Getting emergency contact numbers');
    try {
      final prefs = await SharedPreferences.getInstance();
      final contactsJson = prefs.getString('emergency_contacts');
      
      if (contactsJson == null || contactsJson.isEmpty) {
        print('MessageService: No emergency contacts found');
        return [];
      }
      
      final List<dynamic> contacts = jsonDecode(contactsJson);
      final List<String> phoneNumbers = contacts
          .map((contact) => contact['phoneNumber'] as String)
          .where((phoneNumber) => phoneNumber.isNotEmpty)
          .toList();
      
      print('MessageService: Found ${phoneNumbers.length} contact numbers');
      return phoneNumbers;
    } catch (e) {
      print('MessageService: Error loading contacts: $e');
      return [];
    }
  }

  /// Initialize and request SMS permissions using the telephony package
  Future<bool> initializeAndRequestPermissions() async {
    if (_initialized) {
      return true;
    }
    
    print('MessageService: Initializing and requesting SMS permissions');
    try {
      // Request SMS permission explicitly first
      var smsStatus = await Permission.sms.request();
      print('MessageService: SMS permission status: $smsStatus');
      
      // Then request through telephony
      final bool? result = await telephony.requestPhoneAndSmsPermissions;
      print('MessageService: Telephony permission request result: $result');
      
      _initialized = result ?? false;
      return _initialized;
    } catch (e) {
      print('MessageService: Error requesting permissions: $e');
      return false;
    }
  }

  /// Send emergency SMS to all emergency contacts
  Future<bool> sendEmergencySMS({String reason = 'emergency'}) async {
    print('MessageService: Preparing to send emergency SMS for reason: $reason');
    
    // Ensure permissions are initialized
    if (!_initialized) {
      bool hasPermission = await initializeAndRequestPermissions();
      if (!hasPermission) {
        print('MessageService: SMS permission denied');
        return false;
      }
    }
    
    final locationService = LocationService();
    final String userName = await _getUserName();
    final List<String> recipients = await _getEmergencyContactNumbers();
    
    if (recipients.isEmpty) {
      print('MessageService: No recipients available');
      return false;
    }
    
    try {
      // Generate a message with the appropriate reason
      final String message = await locationService.generateLocationMessage(userName, reason: reason);
      print('MessageService: Sending message: $message');
      print('MessageService: Sending to ${recipients.length} recipients');
      
      // Try both direct SMS methods to ensure delivery
      bool result = await _sendSMSDirectly(message, recipients);
      
      if (!result) {
        // Fallback to the legacy method if direct sending fails
        result = await _sendSMS(message, recipients);
      }
      
      print('MessageService: SMS sending completed with result: $result');
      return result;
    } catch (e) {
      print('MessageService: Error in sendEmergencySMS: $e');
      return false;
    }
  }

  /// Send perimeter breach alert to emergency contacts
  Future<bool> sendPerimeterBreachAlert() async {
    print('MessageService: Sending perimeter breach alert');
    return sendEmergencySMS(reason: 'perimeter_breach');
  }

  /// Check if emergency contacts exist
  Future<bool> hasEmergencyContacts() async {
    final contacts = await _getEmergencyContactNumbers();
    return contacts.isNotEmpty;
  }
  
  /// Send SMS directly without user interaction using another_telephony package
  Future<bool> _sendSMSDirectly(String message, List<String> recipients) async {
    print('MessageService: _sendSMSDirectly called with message: $message');
    print('MessageService: Recipients: $recipients');
    
    try {
      bool allSuccessful = true;
      
      for (String recipient in recipients) {
        print('MessageService: Sending SMS directly to $recipient');
        
        try {
          // Use telephony.sendSms with the updated API
          telephony.sendSms(
            to: recipient,
            message: message,
            statusListener: (SendStatus status) {
              print('MessageService: SMS status for $recipient: $status');
            },
          );
          print('MessageService: SMS sent to $recipient');
          
          // Small delay between sending messages to avoid rate limiting
          await Future.delayed(const Duration(milliseconds: 300));
          
        } catch (e) {
          print('MessageService: Failed to send SMS to $recipient: $e');
          allSuccessful = false;
        }
      }
      
      return allSuccessful;
    } catch (e) {
      print('MessageService: Error sending SMS: $e');
      return false;
    }
  }
  
  /// Legacy method that requires user interaction
  Future<bool> _sendSMS(String message, List<String> recipients) async {
    print('MessageService: _sendSMS called with message: $message');
    print('MessageService: Recipients: $recipients');
    
    try {
      // The sms_mms package requires sending to each recipient individually
      bool allSuccessful = true;
      
      for (String recipient in recipients) {
        print('MessageService: Sending SMS to $recipient');
        
        try {
          // Call SmsMms.send method
          SmsMms.send(message: message, recipients: [recipient]);
          print('MessageService: SMS sent to $recipient');
          
          // Small delay between sending messages
          await Future.delayed(const Duration(milliseconds: 300));
        } catch (e) {
          print('MessageService: Failed to send SMS to $recipient: $e');
          allSuccessful = false;
        }
      }
      
      return allSuccessful;
    } catch (e) {
      print('MessageService: Error sending SMS: $e');
      return false;
    }
  }
}