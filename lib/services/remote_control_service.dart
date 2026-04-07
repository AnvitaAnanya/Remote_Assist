import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridge to the native Android RemoteControlService (Accessibility Service)
/// and the FloatingButtonService (overlay revoke button).
///
/// Provides methods to:
/// - Check / enable the accessibility service
/// - Inject gestures (tap, swipe, long press)
/// - Show / hide a floating overlay button that revokes remote control
class RemoteControlService {
  static const _channel =
      MethodChannel('com.example.remote_assist/remote_control');

  /// Callback fired when the elder taps the floating revoke button
  /// (works system-wide, even when another app is in the foreground).
  static VoidCallback? onFloatingButtonClicked;

  /// Must be called once at startup to register the platform → Flutter callback.
  static void init() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onFloatingButtonClicked') {
        debugPrint('RemoteControlService: Floating button tapped — revoking');
        onFloatingButtonClicked?.call();
      }
    });
  }

  // ─── Accessibility service ───────────────────────────────────────────────

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

  // ─── Overlay permission ──────────────────────────────────────────────────

  /// Returns true if the app has permission to draw over other apps.
  static Future<bool> canDrawOverlays() async {
    try {
      final result = await _channel.invokeMethod<bool>('canDrawOverlays');
      return result ?? false;
    } catch (e) {
      debugPrint('RemoteControlService: Error checking overlay permission: $e');
      return false;
    }
  }

  /// Opens the system settings page to request overlay permission.
  static Future<void> requestOverlayPermission() async {
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } catch (e) {
      debugPrint('RemoteControlService: Error requesting overlay permission: $e');
    }
  }

  // ─── Floating revoke button ──────────────────────────────────────────────

  /// Shows the floating orange revoke button on top of all apps.
  /// Returns false if overlay permission is not granted.
  static Future<bool> showFloatingButton() async {
    try {
      final result = await _channel.invokeMethod<bool>('showFloatingButton');
      return result ?? false;
    } catch (e) {
      debugPrint('RemoteControlService: Error showing floating button: $e');
      return false;
    }
  }

  /// Hides the floating revoke button.
  static Future<void> hideFloatingButton() async {
    try {
      await _channel.invokeMethod('hideFloatingButton');
    } catch (e) {
      debugPrint('RemoteControlService: Error hiding floating button: $e');
    }
  }

  // ─── Gesture injection ───────────────────────────────────────────────────

  /// Injects a tap at normalized coordinates (0.0 – 1.0) on the elder's screen.
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

  /// Injects a swipe gesture.
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

  /// Injects a long press at normalized coordinates (0.0 – 1.0).
  static Future<bool> injectLongPress(double normX, double normY) async {
    try {
      final result = await _channel.invokeMethod<bool>('injectLongPress', {
        'x': normX,
        'y': normY,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('RemoteControlService: Error injecting long press: $e');
      return false;
    }
  }

  /// Cancels any ongoing gesture (e.g. ends a long press early).
  static Future<bool> cancelGesture() async {
    try {
      final result = await _channel.invokeMethod<bool>('cancelGesture');
      return result ?? false;
    } catch (e) {
      debugPrint('RemoteControlService: Error cancelling gesture: $e');
      return false;
    }
  }
}
