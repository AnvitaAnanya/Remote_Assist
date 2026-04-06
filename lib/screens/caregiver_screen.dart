import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/constants.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/webrtc_service.dart';
import 'call_screen.dart';

class CaregiverHomeScreen extends StatefulWidget {
  const CaregiverHomeScreen({super.key});

  @override
  State<CaregiverHomeScreen> createState() => _CaregiverHomeScreenState();
}

class _CaregiverHomeScreenState extends State<CaregiverHomeScreen>
    with SingleTickerProviderStateMixin {
  final FirestoreService _firestoreService = FirestoreService();
  WebRTCService? _webrtcService;
  bool _isAnswering = false;

  // Pulse animation for the incoming call ring
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim =
        Tween<double>(begin: 0.92, end: 1.0).animate(_pulseController);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _webrtcService?.hangUp();
    super.dispose();
  }

  Future<void> _acceptCall(String callId, String elderId) async {
    if (_isAnswering) return;
    setState(() => _isAnswering = true);

    try {
      final caregiverId = FirebaseAuth.instance.currentUser!.uid;
      _webrtcService = WebRTCService();
      await _webrtcService!.answerCallAsCaregiver(callId, caregiverId);

      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CallScreen(
              role: 'caregiver',
              callId: callId,
              webrtcService: _webrtcService!,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('CaregiverScreen: Error answering call: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not join call: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAnswering = false);
    }
  }

  Future<void> _declineCall(String callId) async {
    await _firestoreService.declineCall(callId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Remote Assist'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async => AuthService().signOut(),
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: _firestoreService.listenForIncomingCalls(),
          builder: (context, snapshot) {
            // ── Loading ────────────────────────────────────────────────────
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _buildIdleView(isLoading: true);
            }

            // ── Firestore error (e.g. missing index, permissions) ──────────
            if (snapshot.hasError) {
              return _buildErrorView(snapshot.error.toString());
            }

            // ── No calls ───────────────────────────────────────────────────
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return _buildIdleView();
            }

            // ── Incoming call ──────────────────────────────────────────────
            final callDoc = snapshot.data!.docs.first;
            final callData = callDoc.data() as Map<String, dynamic>;
            final callId = callDoc.id;
            final elderId = callData['elderId'] as String? ?? '';

            return _buildIncomingCallView(callId: callId, elderId: elderId);
          },
        ),
      ),
    );
  }

  // ─── Idle / no incoming calls ──────────────────────────────────────────────

  Widget _buildIdleView({bool isLoading = false}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          _buildSectionHeader('Active Sessions'),
          const SizedBox(height: 16),

          // Status card
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.grey.shade100, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                            strokeWidth: 3,
                          ),
                        )
                      : const Icon(
                          Icons.support_agent,
                          color: AppColors.primary,
                          size: 48,
                        ),
                ),
                const SizedBox(height: 20),
                Text(
                  isLoading ? 'Checking for calls…' : 'No Incoming Requests',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'You\'ll be notified here as soon as\nsomeone needs your help.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Availability row
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.07),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                Icon(Icons.circle, color: Color(0xFF2A7B62), size: 12),
                SizedBox(width: 10),
                Text(
                  'Available & listening for requests',
                  style: TextStyle(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Privacy badge
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.verified_user_outlined,
                  color: AppColors.primaryDark, size: 16),
              SizedBox(width: 8),
              Text(
                'PRIVACY PROTECTED MODE',
                style: TextStyle(
                  color: AppColors.primaryDark,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Error view ─────────────────────────────────────────────────────────────

  Widget _buildErrorView(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Could not listen for calls',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Incoming call UI ───────────────────────────────────────────────────────

  Widget _buildIncomingCallView({
    required String callId,
    required String elderId,
  }) {
    return FutureBuilder<String>(
      future: _firestoreService.getUserName(elderId),
      builder: (context, nameSnap) {
        final callerName = nameSnap.data ?? 'Someone';

        return SingleChildScrollView(
          padding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSectionHeader('Incoming Request'),
              const SizedBox(height: 24),

              // ── Animated call card ──────────────────────────────────────
              ScaleTransition(
                scale: _pulseAnim,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF2A7B62), Color(0xFF1D5A47)],
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.4),
                        blurRadius: 28,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    children: [
                      // Caller avatar
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white.withOpacity(0.4), width: 2),
                        ),
                        child: const Icon(Icons.person,
                            color: Colors.white, size: 44),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'INCOMING CALL',
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        callerName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Requesting remote assistance',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Encrypted indicator row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'End-to-end encrypted',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.orange,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Waiting…',
                        style: TextStyle(
                          color: Colors.orange,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                backgroundColor: AppColors.primary.withOpacity(0.1),
                color: AppColors.primary,
              ),
              const SizedBox(height: 36),

              // ── Accept button ───────────────────────────────────────────
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 58),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 4,
                ),
                onPressed:
                    _isAnswering ? null : () => _acceptCall(callId, elderId),
                icon: _isAnswering
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  _isAnswering ? 'Connecting…' : 'Accept Request',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 14),

              // ── Decline button ──────────────────────────────────────────
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 58),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                onPressed: () => _declineCall(callId),
                icon: const Icon(Icons.cancel_outlined,
                    color: AppColors.textPrimary),
                label: const Text(
                  'Decline',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 17,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Privacy badge
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.verified_user_outlined,
                      color: AppColors.primaryDark, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'PRIVACY PROTECTED MODE',
                    style: TextStyle(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        const Icon(Icons.help_center_outlined, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
