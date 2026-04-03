import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import 'login_screen.dart';
import 'elder_main_nav.dart';
import 'caregiver_screen.dart';
import 'role_selection_screen.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData && snapshot.data != null) {
          // User is signed in, check their role
          return FutureBuilder<String?>(
            future: FirestoreService().getUserRole(snapshot.data!.uid),
            builder: (context, roleSnapshot) {
              if (roleSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              if (roleSnapshot.hasData && roleSnapshot.data != null) {
                final role = roleSnapshot.data!;
                debugPrint("AuthWrapper: Found role '$role'. Moving to dashboard.");
                if (role == 'elder') {
                  return const ElderMainNav();
                } else if (role == 'caregiver') {
                  return const CaregiverHomeScreen();
                }
              }
              debugPrint("AuthWrapper: No role found. Moving to RoleSelectionScreen.");
              // Role not found or not set
              return const RoleSelectionScreen();
            },
          );
        }

        // User is not signed in
        return const LoginScreen();
      },
    );
  }
}
