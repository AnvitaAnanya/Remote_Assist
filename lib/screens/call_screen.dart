import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/webrtc_service.dart';

/// Full-screen video call UI shared by both elder (role='elder') and
/// caregiver (role='caregiver').
///
/// [webrtcService] must already have startCallAsElder / answerCallAsCaregiver
/// called before this screen is pushed — the service holds the live streams.
class CallScreen extends StatefulWidget {
  final String role; // 'elder' | 'caregiver'
  final String callId;
  final WebRTCService webrtcService;

  const CallScreen({
    super.key,
    required this.role,
    required this.callId,
    required this.webrtcService,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  bool _isMicOn = true;
  bool _isCameraOn = true;
  bool _showControls = true;
  Timer? _controlsTimer;

  @override
  void initState() {
    super.initState();
    _initRenderers();
    _startControlsTimer();

    // Listen for status changes (call ended externally)
    widget.webrtcService.status.addListener(_onStatusChanged);
    // Listen for streams becoming available
    widget.webrtcService.localStream.addListener(_onLocalStreamChanged);
    widget.webrtcService.remoteStream.addListener(_onRemoteStreamChanged);
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    // Attach existing streams if already available
    _onLocalStreamChanged();
    _onRemoteStreamChanged();
  }

  void _onLocalStreamChanged() {
    final stream = widget.webrtcService.localStream.value;
    if (stream != null && mounted) {
      setState(() => _localRenderer.srcObject = stream);
    }
  }

  void _onRemoteStreamChanged() {
    final stream = widget.webrtcService.remoteStream.value;
    if (stream != null && mounted) {
      setState(() => _remoteRenderer.srcObject = stream);
    }
  }

  void _onStatusChanged() {
    final s = widget.webrtcService.status.value;
    if (s == CallStatus.ended && mounted) {
      _navigateBack();
    }
    if (mounted) setState(() {});
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _resetControlsTimer() {
    setState(() => _showControls = true);
    _startControlsTimer();
  }

  Future<void> _hangUp() async {
    await widget.webrtcService.hangUp();
    if (mounted) _navigateBack();
  }

  void _navigateBack() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    widget.webrtcService.status.removeListener(_onStatusChanged);
    widget.webrtcService.localStream.removeListener(_onLocalStreamChanged);
    widget.webrtcService.remoteStream.removeListener(_onRemoteStreamChanged);
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final status = widget.webrtcService.status.value;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _resetControlsTimer,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Remote video (full-screen) ──────────────────────────────────
            _remoteRenderer.srcObject != null
                ? RTCVideoView(
                    _remoteRenderer,
                    objectFit:
                        RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  )
                : _buildWaitingOverlay(status),

            // ── Local PiP (bottom-right) ────────────────────────────────────
            Positioned(
              bottom: 120,
              right: 16,
              width: 100,
              height: 140,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _localRenderer.srcObject != null
                    ? RTCVideoView(
                        _localRenderer,
                        mirror: true,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      )
                    : Container(
                        color: Colors.grey.shade900,
                        child: const Icon(Icons.videocam_off,
                            color: Colors.white54),
                      ),
              ),
            ),

            // ── Status badge ────────────────────────────────────────────────
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedOpacity(
                  opacity: status == CallStatus.connected ? 0 : 1,
                  duration: const Duration(milliseconds: 500),
                  child: _StatusBadge(status: status),
                ),
              ),
            ),

            // ── Controls overlay ────────────────────────────────────────────
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              bottom: _showControls ? 32 : -120,
              left: 0,
              right: 0,
              child: _buildControls(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaitingOverlay(CallStatus status) {
    String msg;
    switch (status) {
      case CallStatus.waiting:
        msg = 'Waiting for caregiver to join…';
        break;
      case CallStatus.connecting:
        msg = 'Connecting…';
        break;
      case CallStatus.ended:
        msg = 'Call ended';
        break;
      default:
        msg = 'Starting camera…';
    }

    return Container(
      color: const Color(0xFF0D1B2A),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              color: Color(0xFF2A7B62),
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            msg,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ControlButton(
            icon: _isMicOn ? Icons.mic : Icons.mic_off,
            color: _isMicOn ? Colors.white : Colors.red,
            label: _isMicOn ? 'Mute' : 'Unmute',
            onTap: () async {
              await widget.webrtcService.toggleMic();
              setState(() => _isMicOn = !_isMicOn);
            },
          ),
          _ControlButton(
            icon: Icons.call_end,
            color: Colors.white,
            backgroundColor: Colors.red,
            label: 'End',
            onTap: _hangUp,
            size: 64,
          ),
          _ControlButton(
            icon: _isCameraOn ? Icons.videocam : Icons.videocam_off,
            color: _isCameraOn ? Colors.white : Colors.red,
            label: _isCameraOn ? 'Camera' : 'Cam off',
            onTap: () async {
              await widget.webrtcService.toggleCamera();
              setState(() => _isCameraOn = !_isCameraOn);
            },
          ),
        ],
      ),
    );
  }
}

// ─── Helper widgets ─────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final CallStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    String label;
    Color color;

    switch (status) {
      case CallStatus.waiting:
        label = '⏳  Waiting for caregiver';
        color = Colors.orange;
        break;
      case CallStatus.connecting:
        label = '🔗  Connecting…';
        color = Colors.amber;
        break;
      case CallStatus.connected:
        label = '✅  Connected';
        color = const Color(0xFF2A7B62);
        break;
      case CallStatus.ended:
        label = 'Call Ended';
        color = Colors.red;
        break;
      default:
        label = '';
        color = Colors.transparent;
    }

    if (label.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.85),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color? backgroundColor;
  final String label;
  final VoidCallback onTap;
  final double size;

  const _ControlButton({
    required this.icon,
    required this.color,
    this.backgroundColor,
    required this.label,
    required this.onTap,
    this.size = 52,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: backgroundColor ?? Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: size * 0.45),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
