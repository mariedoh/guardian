import 'package:flutter/material.dart';
import 'package:guardian/functions/emergency_shaker.dart';
import 'package:guardian/screens/home.dart';

void main() async {
  // Ensure Flutter binding is initialized before using platform channels
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize emergency service with error handling
  try {
    debugPrint('Initializing emergency service...');
    final emergencyService = EmergencyService();
    await emergencyService.init();
    debugPrint('Emergency service initialized successfully');
  } catch (e) {
    debugPrint('Failed to initialize emergency service: $e');
    // Continue execution even if emergency service fails
  }
  
  runApp(const GuardianAngelApp());
}

class GuardianAngelApp extends StatelessWidget {
  const GuardianAngelApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return  MaterialApp(
      title: 'Guardian Angel',
      // Theme settings for light and dark mode
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
      ),
      darkTheme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.grey[900],
      ),
      home: HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}