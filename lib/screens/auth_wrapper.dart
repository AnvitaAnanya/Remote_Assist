import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../core/constants.dart';
import 'login_screen.dart';
import 'elder_main_nav.dart';
import 'caregiver_main_nav.dart';
import 'role_selection_screen.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Show loading while Firebase initializes
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _SplashLoadingScreen(message: "Initializing...");
        }

        // Not signed in → go to login
        if (!snapshot.hasData || snapshot.data == null) {
          debugPrint("AuthWrapper: No user. Showing LoginScreen.");
          return const LoginScreen();
        }

        // Signed in → fetch role from Firestore
        final user = snapshot.data!;
        debugPrint("AuthWrapper: User ${user.uid} is signed in. Fetching role...");

        return _RoleRouter(uid: user.uid);
      },
    );
  }
}

/// Separate widget so that role fetch only re-runs when uid changes.
class _RoleRouter extends StatefulWidget {
  final String uid;
  const _RoleRouter({required this.uid});

  @override
  State<_RoleRouter> createState() => _RoleRouterState();
}

class _RoleRouterState extends State<_RoleRouter> {
  late Future<String?> _roleFuture;

  @override
  void initState() {
    super.initState();
    _roleFuture = FirestoreService().getUserRole(widget.uid);
    debugPrint("_RoleRouter: Initiating role fetch for uid=${widget.uid}");
  }

  @override
  void didUpdateWidget(_RoleRouter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      setState(() {
        _roleFuture = FirestoreService().getUserRole(widget.uid);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _roleFuture,
      builder: (context, roleSnapshot) {
        if (roleSnapshot.connectionState == ConnectionState.waiting) {
          return const _SplashLoadingScreen(message: "Loading your profile...");
        }

        if (roleSnapshot.hasError) {
          debugPrint("_RoleRouter: Error fetching role: ${roleSnapshot.error}");
          return const _SplashLoadingScreen(message: "Loading your profile...");
        }

        final role = roleSnapshot.data;
        debugPrint("_RoleRouter: Role fetched = '$role'");

        if (role == 'elder') {
          return const ElderMainNav();
        } else if (role == 'caregiver') {
          return const CaregiverMainNav();
        } else {
          // No role found → user needs to pick a role
          debugPrint("_RoleRouter: No role set. Showing RoleSelectionScreen.");
          return const RoleSelectionScreen();
        }
      },
    );
  }
}

/// A polished loading/splash screen shown during async operations.
class _SplashLoadingScreen extends StatelessWidget {
  final String message;
  const _SplashLoadingScreen({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "REMOTE ASSIST",
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: AppColors.primary,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
