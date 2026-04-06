import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/webrtc_service.dart';

/// Full-screen video call UI shared by both elder (role='elder') and
/// caregiver (role='caregiver').
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
  bool _isScreenSharing = false;
  bool _showControls = true;
  bool _isSwitchingCamera = false;
  bool _isTogglingScreenShare = false;
  Timer? _controlsTimer;

  @override
  void initState() {
    super.initState();
    _initRenderers();
    _startControlsTimer();

    widget.webrtcService.status.addListener(_onStatusChanged);
    widget.webrtcService.localStream.addListener(_onLocalStreamChanged);
    widget.webrtcService.remoteStream.addListener(_onRemoteStreamChanged);
    widget.webrtcService.isScreenSharing.addListener(_onScreenShareChanged);
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    _onLocalStreamChanged();
    _onRemoteStreamChanged();
  }

  void _onLocalStreamChanged() {
    final stream = widget.webrtcService.localStream.value;
    if (mounted) {
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

  void _onScreenShareChanged() {
    if (mounted) setState(() => _isScreenSharing = widget.webrtcService.isScreenSharing.value);
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 5), () {
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

  Future<void> _switchCamera() async {
    if (_isSwitchingCamera || _isScreenSharing) return;
    setState(() => _isSwitchingCamera = true);
    try {
      await widget.webrtcService.switchCamera();
    } finally {
      if (mounted) setState(() => _isSwitchingCamera = false);
    }
  }

  Future<void> _toggleScreenShare() async {
    if (_isTogglingScreenShare) return;
    setState(() => _isTogglingScreenShare = true);
    try {
      await widget.webrtcService.toggleScreenShare();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Screen share unavailable: $e'),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isTogglingScreenShare = false);
    }
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    widget.webrtcService.status.removeListener(_onStatusChanged);
    widget.webrtcService.localStream.removeListener(_onLocalStreamChanged);
    widget.webrtcService.remoteStream.removeListener(_onRemoteStreamChanged);
    widget.webrtcService.isScreenSharing.removeListener(_onScreenShareChanged);
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  bool get _isElder => widget.role == 'elder';

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
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  )
                : _buildWaitingOverlay(status),

            // ── Local PiP (bottom-right) ────────────────────────────────────
            Positioned(
              bottom: 160,
              right: 16,
              width: 100,
              height: 140,
              child: GestureDetector(
                // Tap PiP to switch camera (quick shortcut)
                onTap: _isElder && !_isScreenSharing ? _switchCamera : null,
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _localRenderer.srcObject != null
                          ? RTCVideoView(
                              _localRenderer,
                              mirror: !_isScreenSharing,
                              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                            )
                          : Container(
                              color: Colors.grey.shade900,
                              child: const Icon(Icons.videocam_off, color: Colors.white54),
                            ),
                    ),
                    // Camera flip hint overlay on PiP
                    if (_isElder && !_isScreenSharing)
                      Positioned(
                        bottom: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.flip_camera_ios,
                              color: Colors.white70, size: 14),
                        ),
                      ),
                    // Screen share indicator on PiP
                    if (_isScreenSharing)
                      Positioned(
                        bottom: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue.withAlpha(200),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('Screen',
                              style: TextStyle(color: Colors.white, fontSize: 9)),
                        ),
                      ),
                  ],
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

            // ── Screen share active banner (elder) ──────────────────────────
            if (_isScreenSharing)
              Positioned(
                top: MediaQuery.of(context).padding.top + 60,
                left: 24,
                right: 24,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade700.withAlpha(230),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.screen_share, color: Colors.white, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Sharing your screen',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),

            // ── Controls overlay ────────────────────────────────────────────
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              bottom: _showControls ? 32 : -180,
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
            child: CircularProgressIndicator(color: Color(0xFF2A7B62), strokeWidth: 3),
          ),
          const SizedBox(height: 24),
          Text(
            msg,
            style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(178),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Secondary row (camera flip + screen share for elder) ──────────
          if (_isElder)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ControlButton(
                    icon: _isSwitchingCamera ? Icons.hourglass_empty : Icons.flip_camera_ios,
                    color: _isScreenSharing ? Colors.white30 : Colors.white,
                    label: 'Flip Cam',
                    onTap: _switchCamera,
                    size: 44,
                  ),
                  const SizedBox(width: 32),
                  _ControlButton(
                    icon: _isScreenSharing ? Icons.stop_screen_share : Icons.screen_share,
                    color: _isScreenSharing ? Colors.blue.shade300 : Colors.white,
                    backgroundColor: _isScreenSharing ? Colors.blue.shade900.withAlpha(180) : null,
                    label: _isScreenSharing ? 'Stop Share' : 'Share Screen',
                    onTap: _toggleScreenShare,
                    size: 44,
                    isLoading: _isTogglingScreenShare,
                  ),
                ],
              ),
            ),
          // ── Divider ───────────────────────────────────────────────────────
          if (_isElder)
            Divider(color: Colors.white12, height: 1, thickness: 1),
          if (_isElder) const SizedBox(height: 12),
          // ── Main controls row ─────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Mic
              _ControlButton(
                icon: _isMicOn ? Icons.mic : Icons.mic_off,
                color: _isMicOn ? Colors.white : Colors.red,
                label: _isMicOn ? 'Mute' : 'Unmute',
                onTap: () async {
                  await widget.webrtcService.toggleMic();
                  setState(() => _isMicOn = !_isMicOn);
                },
              ),
              // Flip camera (caregiver — shown in main row since no secondary row)
              if (!_isElder)
                _ControlButton(
                  icon: _isSwitchingCamera ? Icons.hourglass_empty : Icons.flip_camera_ios,
                  color: Colors.white,
                  label: 'Flip Cam',
                  onTap: _switchCamera,
                ),
              // Hang up
              _ControlButton(
                icon: Icons.call_end,
                color: Colors.white,
                backgroundColor: Colors.red,
                label: 'End',
                onTap: _hangUp,
                size: 64,
              ),
              // Camera on/off
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
        ],
      ),
    );
  }
}

// ─── Helper widgets ──────────────────────────────────────────────────────────

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
        color: color.withAlpha(218),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
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
  final bool isLoading;

  const _ControlButton({
    required this.icon,
    required this.color,
    this.backgroundColor,
    required this.label,
    required this.onTap,
    this.size = 52,
    this.isLoading = false,
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
              color: backgroundColor ?? Colors.white.withAlpha(38),
              shape: BoxShape.circle,
            ),
            child: isLoading
                ? Padding(
                    padding: EdgeInsets.all(size * 0.28),
                    child: const CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : Icon(icon, color: color, size: size * 0.44),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
