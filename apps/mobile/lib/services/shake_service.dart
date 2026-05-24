import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';

class ShakeService {
  static final ShakeService _instance = ShakeService._internal();
  factory ShakeService() => _instance;
  ShakeService._internal();

  StreamSubscription? _subscription;
  DateTime? _lastShakeTime;
  
  // Acceleration threshold to qualify as a shake
  static const double _shakeThreshold = 14.0; 
  static const Duration _cooldown = Duration(seconds: 2);

  /// Starts listening to accelerometer sensor feeds
  void startListening(Function onShakeTriggered) {
    _subscription?.cancel();
    
    // userAccelerometerEventStream() is the non-deprecated successor to the
    // removed global userAccelerometerEvents stream.
    _subscription = userAccelerometerEventStream().listen((UserAccelerometerEvent event) {
      final double x = event.x;
      final double y = event.y;
      final double z = event.z;

      // Compute total G-force magnitude excluding gravity (user acceleration)
      final double gForce = (x * x + y * y + z * z);
      
      if (gForce > _shakeThreshold * _shakeThreshold) {
        final now = DateTime.now();
        if (_lastShakeTime == null || now.difference(_lastShakeTime!) > _cooldown) {
          _lastShakeTime = now;
          onShakeTriggered();
        }
      }
    });
  }

  /// Stops sensor feed streams
  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }
}
