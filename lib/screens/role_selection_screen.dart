import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../main.dart';
import 'elder_main_nav.dart';
import 'caregiver_screen.dart';

import 'package:firebase_auth/firebase_auth.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import 'auth_wrapper.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  bool _isLoading = false;

  Future<void> _selectRole(String role, Widget nextScreen) async {
    if (_isLoading) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      setState(() => _isLoading = true);
      try {
        await FirestoreService().createUserProfile(
          uid: user.uid,
          email: user.email ?? '',
          name: user.displayName ?? 'User',
          role: role,
        );
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => nextScreen),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to save role: $e')),
          );
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Widget _buildRoleCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isPrimary,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          color: isPrimary ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: isPrimary ? null : Border.all(color: AppColors.primary, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isPrimary ? Colors.white.withOpacity(0.2) : AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isPrimary ? Colors.white : AppColors.primary,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isPrimary ? Colors.white : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isPrimary ? Colors.white70 : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName ?? (user?.email?.split('@').first ?? 'User');

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              // Top Bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   Row(
                    children: [
                      const Icon(Icons.shield_outlined, color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        displayName,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.logout, color: Colors.grey),
                        onPressed: () async {
                          await AuthService().signOut();
                          if (mounted) {
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(builder: (_) => const AuthWrapper()),
                              (route) => false,
                            );
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.dark_mode_outlined, color: AppColors.primary),
                        onPressed: () {
                          appThemeMode.value = appThemeMode.value == ThemeMode.light 
                              ? ThemeMode.dark 
                              : ThemeMode.light;
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Header
              const Text(
                "REMOTE ASSIST",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primary,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Choose your role to start a\nsecure session",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),

              // Elder Role Card
              _buildRoleCard(
                title: "I Need Help",
                subtitle: "Receive technical\nassistance",
                icon: Icons.pan_tool_outlined,
                isPrimary: true,
                onTap: () => _selectRole('elder', const ElderMainNav()),
              ),
              const SizedBox(height: 12),

              // Caregiver Role Card
              _buildRoleCard(
                title: "I Will Help\nSomeone",
                subtitle: "Assist a family member",
                icon: Icons.support_agent,
                isPrimary: false,
                onTap: () => _selectRole('caregiver', const CaregiverHomeScreen()),
              ),
              const SizedBox(height: 12),

              // Footer
              Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.verified_user_outlined, color: AppColors.primaryDark, size: 16),
                      SizedBox(width: 8),
                      Text(
                        "END-TO-END ENCRYPTED",
                        style: TextStyle(
                          color: AppColors.primaryDark,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "By continuing, you agree to our",
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Terms & Privacy Policy",
                    style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        if (_isLoading)
          Container(
            color: Colors.black12,
            child: const Center(child: CircularProgressIndicator()),
          ),
        ],
      )),
    );
  }
}
