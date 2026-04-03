import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Stream of user auth state
  Stream<User?> get userStream => _auth.authStateChanges();

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Sign In
  Future<User?> signInWithEmailPassword(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return result.user;
    } on FirebaseAuthException catch (e) {
      debugPrint("AuthService Error (SignIn) [${e.code}]: ${e.message}");
      rethrow;
    } catch (e) {
      debugPrint("AuthService Error (SignIn) Unknown: $e");
      rethrow;
    }
  }

  // Sign Up
  Future<User?> signUpWithEmailPassword(String email, String password, String name) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      // Update display name
      await result.user?.updateDisplayName(name);
      
      return result.user;
    } on FirebaseAuthException catch (e) {
      debugPrint("AuthService Error (SignUp) [${e.code}]: ${e.message}");
      rethrow;
    } catch (e) {
      debugPrint("AuthService Error (SignUp) Unknown: $e");
      rethrow;
    }
  }

  // Sign Out
  Future<void> signOut() async {
    await _auth.signOut();
  }
}
