import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Create a user profile in Firestore
  Future<void> createUserProfile({
    required String uid,
    required String email,
    required String name,
    required String role, 
  }) async {
    try {
      await _db.collection('users').doc(uid).set({
        'uid': uid,
        'email': email,
        'name': name,
        'role': role,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Firestore Error (createUserProfile): $e");
      rethrow;
    }
  }

  // Update FCM device token for push notifications
  Future<void> updateUserToken(String uid, String token) async {
    try {
      await _db.collection('users').doc(uid).set({
        'fcmToken': token,
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Firestore Error (updateUserToken): $e");
    }
  }

  // Fetch a user's role
  Future<String?> getUserRole(String uid) async {
    try {
      DocumentSnapshot doc = await _db.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;
        return data['role'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint("Firestore Error (getUserRole): $e");
      return null;
    }
  }
}
