import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridge to the native Android RemoteControlService (Accessibility Service).
/// Provides methods to check/enable the service and inject tap gestures.
class RemoteControlService {
  static const _channel =
      MethodChannel('com.example.remote_assist/remote_control');

  /// Returns true if the Accessibility Service is currently enabled and running.
  static Future<bool> isAccessibilityEnabled() async {
    try {
      final result = await _channel.invokeMethod<bool>('isAccessibilityEnabled');
      return result ?? false;
    } catch (e) {
      debugPrint('RemoteControlService: Error checking accessibility: $e');
      return false;
    }
  }

  /// Opens the Android Accessibility Settings page so the user can enable
  /// the Remote Assist accessibility service.
  static Future<void> openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
    } catch (e) {
      debugPrint('RemoteControlService: Error opening settings: $e');
    }
  }

  /// Injects a tap at normalized coordinates (0.0 – 1.0) on the elder's screen.
  /// The native side converts these to actual screen pixels.
  static Future<bool> injectTap(double normX, double normY) async {
    try {
      final result = await _channel.invokeMethod<bool>('injectTap', {
        'x': normX,
        'y': normY,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('RemoteControlService: Error injecting tap: $e');
      return false;
    }
  }

  /// Injects a swipe from (normStartX, normStartY) to (normEndX, normEndY)
  /// over [durationMs] milliseconds on the elder's screen.
  /// All coordinates are normalized (0.0 – 1.0).
  static Future<bool> injectSwipe(
    double normStartX,
    double normStartY,
    double normEndX,
    double normEndY,
    int durationMs,
  ) async {
    try {
      final result = await _channel.invokeMethod<bool>('injectSwipe', {
        'startX': normStartX,
        'startY': normStartY,
        'endX': normEndX,
        'endY': normEndY,
        'duration': durationMs,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('RemoteControlService: Error injecting swipe: $e');
      return false;
    }
  }
}
