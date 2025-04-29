import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';

typedef OrientationCallback = void Function(int degrees);

class OrientationService {
  int _deviceOrientationDegrees = 0;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  final OrientationCallback? onChanged;

  OrientationService({this.onChanged});

  int get orientationDegrees => _deviceOrientationDegrees;

  void start() {
    _accelSub = accelerometerEvents.listen(_onAccelerometerEvent);
  }

  void stop() {
    _accelSub?.cancel();
  }

  void _onAccelerometerEvent(AccelerometerEvent event) {
    final double x = event.x;
    final double y = event.y;
    int newOrientation;
    if (x.abs() < 4 && y < -6) {
      newOrientation = 0; // portrait up
    } else if (x.abs() < 4 && y > 6) {
      newOrientation = 180; // portrait down
    } else if (x > 6) {
      newOrientation = 270; // landscape left
    } else if (x < -6) {
      newOrientation = 90; // landscape right
    } else {
      newOrientation = _deviceOrientationDegrees;
    }
    if (newOrientation != _deviceOrientationDegrees) {
      _deviceOrientationDegrees = newOrientation;
      if (onChanged != null) onChanged!(newOrientation);
    }
  }
}
