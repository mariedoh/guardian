import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:flutter_background_video_recorder/flutter_bvr_platform_interface.dart';
import 'package:flutter_background_video_recorder/flutter_bvr.dart';
import 'package:shake/shake.dart';

class Shaker {
  late final StreamSubscription<int> _timerListener;
  bool _isRecording = false;
  bool _recorderBusy = false;
  StreamSubscription<int?>? _streamSubscription;
  final _flutterBackgroundVideoRecorderPlugin = FlutterBackgroundVideoRecorder();
  ShakeDetector? _detector;

  Future<void> getInitialRecordingStatus() async {
    _isRecording = await _flutterBackgroundVideoRecorderPlugin.getVideoRecordingStatus() == 1;
  }

  void listenRecordingState() {
    _streamSubscription =
        _flutterBackgroundVideoRecorderPlugin.recorderState.listen((event) {
      switch (event) {
        case 1:
          _isRecording = true;
          _recorderBusy = true;
          break;
        case 2:
          _isRecording = false;
          _recorderBusy = false;
          break;
        case 3:
          _recorderBusy = true;
          break;
        case -1:
          _isRecording = false;
          break;
        default:
          return;
      }
    });
  }

  void startDetector() {
    double _shakeThreshold = 2.7;
    bool _useFilter = false;
    int _minimumShakeCount = 1;

    _detector = ShakeDetector.autoStart(
      onPhoneShake: (ShakeEvent event) {
        if (!_isRecording && !_recorderBusy) {
            startRecording("Rear camera");
        }
      },
      minimumShakeCount: _minimumShakeCount,
      shakeSlopTimeMS: 500,
      shakeCountResetTime: 3000,
      shakeThresholdGravity: _shakeThreshold,
      useFilter: _useFilter,
    );
  }

  Future<void> startRecording(String cameraFacing) async {
    int minutes = 0;
    int second = 30;
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String timing = await prefs.getString("film_duration") ?? "";
    if (timing != ""){
      List<String> parts = timing.split(":");
      minutes = int.parse(parts[0]);
      second = int.parse(parts[1]);
    }

    await _flutterBackgroundVideoRecorderPlugin.startVideoRecording(
      folderName: "Example Recorder",
      cameraFacing: cameraFacing == "Rear camera"
          ? CameraFacing.rearCamera
          : CameraFacing.frontCamera,
      notificationTitle: "Example Notification Title",
      notificationText: "Example Notification Text",
      showToast: false,
    );
    Timer( Duration(seconds: second, minutes: minutes), () async{
      await _flutterBackgroundVideoRecorderPlugin.stopVideoRecording();
    });
  }
  void stopShakeDetection() {
    _detector?.stopListening();
  }
  void dispose() {
    _timerListener.cancel();
    _detector?.stopListening();
  }
}