import 'package:flutter/material.dart';
import 'package:guardian/functions/perimter_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

class PerimeterLockPage extends StatefulWidget {
  const PerimeterLockPage({Key? key}) : super(key: key);

  @override
  _PerimeterLockPageState createState() => _PerimeterLockPageState();
}

class _PerimeterLockPageState extends State<PerimeterLockPage> {
  
  bool _perimeterLockActive = false;
  bool _isLoading = true;
  int _safeDistance = 50; // Default distance in meters
  LatLng? _centerLocation;
  final PerimeterService _perimeterService = PerimeterService();
  GoogleMapController? _mapController;
  Set<Circle> _circles = {};
  bool _mapReady = false;
  
  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _loadSettings();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    // Just check if location permission is granted, we'll request it when needed
    final status = await Permission.location.status;
    if (status.isDenied || status.isPermanentlyDenied) {
      // Show a notification that permission is needed
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Location permission is required for Perimeter Lock to work'),
                duration: Duration(seconds: 3),
              ),
            );
          }
        });
      }
    }
  }

  Future<void> _loadSettings() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final lat = prefs.getDouble('perimeter_center_lat');
      final lng = prefs.getDouble('perimeter_center_lng');
      
      if (!mounted) return;
      
      setState(() {
        _perimeterLockActive = prefs.getBool('perimeter_active') ?? false;
        _safeDistance = prefs.getInt('safe_distance') ?? 50;
        
        if (lat != null && lng != null) {
          _centerLocation = LatLng(lat, lng);
        }
        
        _isLoading = false;
      });
      
      // After settings are loaded, check if perimeter is active in PerimeterService
      if (_perimeterLockActive && mounted) {
        final isActuallyMonitoring = _perimeterService.isMonitoring();
        if (!isActuallyMonitoring && _centerLocation != null) {
          // Restart monitoring if it should be active but isn't
          await _perimeterService.startMonitoring(
            _centerLocation!.latitude,
            _centerLocation!.longitude,
            _safeDistance
          );
        } else if (!isActuallyMonitoring && mounted) {
          // If we're supposed to be monitoring but don't have a center location, get current location
          await _updateCenterLocation();
          if (_centerLocation != null && mounted) {
            await _perimeterService.startMonitoring(
              _centerLocation!.latitude,
              _centerLocation!.longitude,
              _safeDistance
            );
          }
        }
      }
      
      if (mounted) {
        _updateCircle();
      }
    } catch (e) {
      print('PerimeterLockPage: Error loading settings: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load settings: $e')),
        );
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _updateCircle() {
    if (_centerLocation != null && mounted) {
      setState(() {
        _circles = {
          Circle(
            circleId: const CircleId('safeZone'),
            center: _centerLocation!,
            radius: _safeDistance.toDouble(),
            fillColor: Colors.green.withOpacity(0.2),
            strokeColor: Colors.green,
            strokeWidth: 2,
          )
        };
      });
      
      // Update map camera if controller is ready
      if (_mapController != null && _mapReady && _centerLocation != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_mapController != null && mounted) {
            _mapController!.animateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(
                  target: _centerLocation!,
                  zoom: 15,
                ),
              ),
            );
          }
        });
      }
    }
  }

  Future<bool> _requestLocationPermission() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return false;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        // Show dialog explaining how to enable in settings
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Location Permission Required'),
              content: const Text(
                'This app needs location permission to monitor your safe zone. Please enable it in your device settings.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await Geolocator.openAppSettings();
                  },
                  child: const Text('OPEN SETTINGS'),
                ),
              ],
            ),
          );
        }
        return false;
      }
      
      return true;
    } catch (e) {
      print('PerimeterLockPage: Error requesting location permission: $e');
      return false;
    }
  }

  Future<void> _togglePerimeterLock(bool value) async {
    // Don't proceed if already in requested state
    if (_perimeterLockActive == value || !mounted) return;
    
    // Check permissions only when enabling
    if (value) {
      bool permissionGranted = await _requestLocationPermission();
      if (!permissionGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permission is required for Perimeter Lock'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // If we don't have a center location yet, get the current location
      if (_centerLocation == null) {
        bool updated = await _updateCenterLocation();
        if (!updated || !mounted) {
          return; // Failed to get location
        }
      }
    }

    // Show loading indicator
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      bool success;
      
      // Update perimeter service first
      if (value && _centerLocation != null) {
        success = await _perimeterService.startMonitoring(
          _centerLocation!.latitude, 
          _centerLocation!.longitude, 
          _safeDistance
        );
      } else {
        success = await _perimeterService.stopMonitoring();
      }
      
      if (!success) {
        throw Exception('Failed to update perimeter monitoring');
      }
      
      // Then update SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('perimeter_active', value);
      
      if (mounted) {
        setState(() {
          _perimeterLockActive = value;
          _isLoading = false;
        });
        
        // Show confirmation dialog only when activated
        if (value) {
          _showPerimeterLockActivatedDialog();
        }
      }
    } catch (e) {
      print('PerimeterLockPage: Error toggling perimeter lock: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update perimeter lock: $e')),
        );
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<bool> _updateCenterLocation() async {
    if (!mounted) return false;
    
    try {
      final location = await _perimeterService.getCurrentLocation();
      if (location != null && mounted) {
        setState(() {
          _centerLocation = LatLng(location.latitude, location.longitude);
        });
        
        // Save to shared preferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('perimeter_center_lat', location.latitude);
        await prefs.setDouble('perimeter_center_lng', location.longitude);
        
        if (mounted) {
          _updateCircle();
        }
        return true;
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not get current location. Please check your GPS and try again.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return false;
      }
    } catch (e) {
      print('PerimeterLockPage: Error updating center location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to get current location: $e')),
        );
      }
      return false;
    }
  }

  void _setNewCenter() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      bool permissionGranted = await _requestLocationPermission();
      if (!permissionGranted || !mounted) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }
      
      bool updated = await _updateCenterLocation();
      if (!updated || !mounted) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }
      
      // If monitoring is active, restart with new center
      if (_perimeterLockActive && _centerLocation != null && mounted) {
        await _perimeterService.startMonitoring(
          _centerLocation!.latitude, 
          _centerLocation!.longitude, 
          _safeDistance
        );
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Center location updated'),
            duration: Duration(seconds: 2),
          ),
        );
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('PerimeterLockPage: Error setting new center: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to set new center: $e')),
        );
      }
    }
  }

  void _showPerimeterLockActivatedDialog() {
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false, // User must tap button to close dialog
      builder: (context) => AlertDialog(
        title: const Text('Perimeter Lock Activated'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Perimeter Lock is now active. If the device moves outside the set perimeter, your emergency contacts will be notified with your location.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 15),
            Text(
              'Safe distance: $_safeDistance meters',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Perimeter Lock'),
        backgroundColor: _perimeterLockActive ? Colors.green : null,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _buildContent(),
    );
  }
  
  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        // Perimeter Lock Status Card
        _buildStatusCard(),
        
        const SizedBox(height: 16),
        
        // Map view Card
        _buildMapCard(),
        
        const SizedBox(height: 16),
        
        // Set current location button
        ElevatedButton.icon(
          icon: const Icon(Icons.my_location),
          label: const Text('SET CURRENT LOCATION AS CENTER'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          onPressed: _setNewCenter,
        ),
        
        const SizedBox(height: 24),
        
        // Safe distance info
        _buildSafeDistanceCard(),
        
        const SizedBox(height: 24),
        
        // How To Use Section
        _buildHowToUseSection(),
        
        const SizedBox(height: 24),
        
        // Important Notes Section
        _buildImportantNotesSection(),
      ],
    );
  }
  
  Widget _buildStatusCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(
              Icons.location_on,
              color: _perimeterLockActive ? Colors.green : Colors.grey,
              size: 36,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Perimeter Lock',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _perimeterLockActive ? Colors.green : null,
                    ),
                  ),
                  Text(
                    _perimeterLockActive
                        ? 'Active - Safe zone monitoring enabled'
                        : 'Inactive - No location monitoring',
                    style: TextStyle(
                      color: _perimeterLockActive ? Colors.green : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: _perimeterLockActive,
              activeColor: Colors.green,
              onChanged: _togglePerimeterLock,
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildMapCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        height: 250,
        padding: const EdgeInsets.all(8.0),
        child: _centerLocation != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _centerLocation!,
                    zoom: 15,
                  ),
                  circles: _circles,
                  onMapCreated: (controller) {
                    _mapController = controller;
                    setState(() {
                      _mapReady = true;
                    });
                    
                    // Add a slight delay to ensure proper rendering
                    Future.delayed(const Duration(milliseconds: 500), () {
                      if (mounted && _centerLocation != null) {
                        controller.animateCamera(
                          CameraUpdate.newCameraPosition(
                            CameraPosition(
                              target: _centerLocation!,
                              zoom: 15,
                            ),
                          ),
                        );
                      }
                    });
                  },
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: true,
                  mapToolbarEnabled: false,
                ),
              )
            : const Center(
                child: Text(
                  'No center location set. Click "Set Current Location as Center" button below.',
                  textAlign: TextAlign.center,
                ),
              ),
      ),
    );
  }
  
  Widget _buildSafeDistanceCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Safe Distance',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Current safe distance: $_safeDistance meters',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),
            const Text(
              'You can adjust the safe distance from the Settings page.',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildHowToUseSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'How To Use',
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
              children: const [
                Text(
                  '1. Set the Center Location',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                Text(
                  'Use the "Set Current Location as Center" button to define the center of your safe zone.',
                ),
                SizedBox(height: 12),
                Text(
                  '2. Activate Perimeter Lock',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                Text(
                  'Toggle the switch to enable the perimeter lock and start monitoring.',
                ),
                SizedBox(height: 12),
                Text(
                  '3. Automatic Alerting',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                Text(
                  'If the device leaves the safe zone, emergency contacts will be automatically notified with the current location.',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildImportantNotesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
              children: const [
                ListTile(
                  leading: Icon(Icons.battery_alert, color: Colors.orange),
                  title: Text('Battery Usage'),
                  subtitle: Text('Perimeter lock uses location services and may use more battery'),
                  contentPadding: EdgeInsets.all(0),
                ),
                ListTile(
                  leading: Icon(Icons.location_on, color: Colors.blue),
                  title: Text('Permissions Required'),
                  subtitle: Text('Location permission must be granted for this feature to work'),
                  contentPadding: EdgeInsets.all(0),
                ),
                ListTile(
                  leading: Icon(Icons.contacts, color: Colors.green),
                  title: Text('Emergency Contacts'),
                  subtitle: Text('Make sure emergency contacts are set up in the Settings page'),
                  contentPadding: EdgeInsets.all(0),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}