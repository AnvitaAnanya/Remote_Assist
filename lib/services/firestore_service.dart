import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─── User Profile ────────────────────────────────────────────────────────

  /// Create a user profile in Firestore
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

  /// Update FCM device token for push notifications
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

  /// Fetch a user's role
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

  /// Fetch a user's display name
  Future<String> getUserName(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        return (doc.data() as Map<String, dynamic>)['name'] as String? ??
            'User';
      }
      return 'User';
    } catch (e) {
      return 'User';
    }
  }

  // ─── Call Signaling ───────────────────────────────────────────────────────

  /// Returns a real-time stream of the first waiting call for the caregiver.
  /// No orderBy — avoids needing a composite Firestore index.
  Stream<QuerySnapshot> listenForIncomingCalls() {
    return _db
        .collection('calls')
        .where('status', isEqualTo: 'waiting')
        .limit(1)
        .snapshots();
  }

  /// Mark a call as ended.
  Future<void> endCall(String callId) async {
    try {
      await _db.collection('calls').doc(callId).update({'status': 'ended'});
    } catch (e) {
      debugPrint("Firestore Error (endCall): $e");
    }
  }

  /// Decline a call — stores the caregiver's name so the elder can display it.
  Future<void> declineCall(String callId, String caregiverName) async {
    try {
      await _db.collection('calls').doc(callId).update({
        'status': 'declined',
        'declinedByName': caregiverName,
      });
    } catch (e) {
      debugPrint("Firestore Error (declineCall): $e");
    }
  }
}
