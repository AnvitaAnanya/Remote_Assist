import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/constants.dart';

class ElderHomeScreen extends StatefulWidget {
  const ElderHomeScreen({super.key});

  @override
  State<ElderHomeScreen> createState() => _ElderHomeScreenState();
}

class _ElderHomeScreenState extends State<ElderHomeScreen> {
  bool _isRequesting = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("REMOTE ASSIST", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await AuthService().signOut();
              // No navigation needed, AuthWrapper will handle it.
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              // Request Help Big Button
              AspectRatio(
                aspectRatio: 1.3,
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.vibrate();
                    setState(() {
                      _isRequesting = !_isRequesting;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    decoration: BoxDecoration(
                      color: _isRequesting ? Colors.orange : AppColors.primary,
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [
                        BoxShadow(
                          color: (_isRequesting ? Colors.orange : AppColors.primary).withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        )
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _isRequesting ? Icons.hourglass_empty : Icons.help_outline,
                            color: Colors.white,
                            size: 64,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _isRequesting ? "Connecting..." : "Request Help",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // Status Indicator
              Container(
                padding: const EdgeInsets.symmetric(vertical: 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.grey.shade100, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isRequesting ? Icons.wifi_calling_3 : Icons.link_off,
                          color: _isRequesting ? Colors.orange : AppColors.error,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isRequesting ? "Waiting for Caregiver" : "Not Connected",
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isRequesting ? "Listening for acceptance" : "System is ready",
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 16),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              
              // Helper text
              Text(
                _isRequesting 
                    ? "Please wait while we reach out to your helper."
                    : "Tap the green button above to\nconnect with your helper.",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}