import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'firestore_service.dart';

class MessagingService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FirestoreService _firestoreService = FirestoreService();

  Future<void> init(String? uid) async {
    // Request permission (mostly for iOS, but good practice)
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('User granted push notification permission');
      
      // Get the token and save it to Firestore if we have a logged-in user
      if (uid != null) {
        String? token = await _fcm.getToken();
        if (token != null) {
          await _firestoreService.updateUserToken(uid, token);
        }

        // Listen for token refreshes
        _fcm.onTokenRefresh.listen((newToken) {
          _firestoreService.updateUserToken(uid, newToken);
        });
      }
    } else {
      debugPrint('User declined or has not accepted permission');
    }
    
    // Handle incoming messages while the app is in the foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Got a message whilst in the foreground!');
      debugPrint('Message data: ${message.data}');

      if (message.notification != null) {
        debugPrint('Message also contained a notification: ${message.notification}');
      }
    });
  }
}
