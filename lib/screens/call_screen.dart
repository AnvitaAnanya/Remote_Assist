import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/webrtc_service.dart';
import '../services/remote_control_service.dart';

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
  bool _isRemoteControlActive = false;
  bool _remoteControlRequested = false;
  Timer? _controlsTimer;

  // Swipe tracking state for the caregiver's pan gesture
  Offset? _swipeStartPosition;
  Offset? _swipeEndPosition;
  DateTime? _swipeStartTime;

  // ─── PiP drag-to-corner state ────────────────────────────────────────────
  static const double _pipWidth = 100;
  static const double _pipHeight = 140;
  static const double _pipMargin = 16;
  Offset? _pipOffset; // current position (null = use default corner)
  bool _isDraggingPip = false;

  @override
  void initState() {
    super.initState();
    _initRenderers();
    _startControlsTimer();

    // Register the floating button callback (elder only).
    // When the elder taps the floating overlay button, revoke remote control.
    if (_isElder) {
      RemoteControlService.init();
      RemoteControlService.onFloatingButtonClicked = _onFloatingButtonClicked;
    }

    widget.webrtcService.status.addListener(_onStatusChanged);
    widget.webrtcService.localStream.addListener(_onLocalStreamChanged);
    widget.webrtcService.remoteStream.addListener(_onRemoteStreamChanged);
    widget.webrtcService.isScreenSharing.addListener(_onScreenShareChanged);
    widget.webrtcService.isRemoteControlActive.addListener(_onRemoteControlChanged);
    widget.webrtcService.remoteControlRequested.addListener(_onControlRequested);
    widget.webrtcService.incomingTouch.addListener(_onIncomingTouch);
    widget.webrtcService.incomingSwipe.addListener(_onIncomingSwipe);
    widget.webrtcService.incomingLongPress.addListener(_onIncomingLongPress);
    widget.webrtcService.incomingLongPressEnd.addListener(_onIncomingLongPressEnd);
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
      setState(() {
        _localRenderer.srcObject = stream;
        // Sync mic button with actual audio track state
        // (prevents inversion after screen share creates a fresh stream)
        final audioTracks = stream?.getAudioTracks() ?? [];
        if (audioTracks.isNotEmpty) {
          _isMicOn = audioTracks.first.enabled;
        }
      });
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

  void _onRemoteControlChanged() {
    final active = widget.webrtcService.isRemoteControlActive.value;
    if (mounted) setState(() => _isRemoteControlActive = active);

    // Elder: show/hide the floating overlay revoke button
    if (_isElder) {
      if (active) {
        RemoteControlService.showFloatingButton();
      } else {
        RemoteControlService.hideFloatingButton();
      }
    }
  }

  void _onControlRequested() {
    if (mounted) {
      setState(() => _remoteControlRequested = widget.webrtcService.remoteControlRequested.value);
      // Show grant/deny dialog on elder side
      if (_remoteControlRequested && _isElder) {
        _showGrantControlDialog();
      }
    }
  }

  void _onIncomingTouch() {
    final touch = widget.webrtcService.incomingTouch.value;
    if (touch != null && _isElder && _isRemoteControlActive) {
      // Inject the tap via the Accessibility Service
      RemoteControlService.injectTap(touch['x']!, touch['y']!);
    }
  }

  void _onIncomingSwipe() {
    final swipe = widget.webrtcService.incomingSwipe.value;
    if (swipe != null && _isElder && _isRemoteControlActive) {
      // Inject the swipe via the Accessibility Service
      RemoteControlService.injectSwipe(
        swipe['startX']!,
        swipe['startY']!,
        swipe['endX']!,
        swipe['endY']!,
        swipe['duration']!.toInt(),
      );
    }
  }

  void _onIncomingLongPress() {
    final lp = widget.webrtcService.incomingLongPress.value;
    if (lp != null && _isElder && _isRemoteControlActive) {
      // Start a long press (holds for 30s, cancelled by _onIncomingLongPressEnd)
      RemoteControlService.injectLongPress(lp['x']!, lp['y']!);
    }
  }

  void _onIncomingLongPressEnd() {
    if (widget.webrtcService.incomingLongPressEnd.value &&
        _isElder &&
        _isRemoteControlActive) {
      // Cancel the ongoing long press gesture
      RemoteControlService.cancelGesture();
    }
  }

  /// Called when the elder taps the floating overlay revoke button.
  /// Works system-wide — the button is visible on top of all apps.
  void _onFloatingButtonClicked() {
    if (!_isRemoteControlActive) return;
    widget.webrtcService.revokeRemoteControl();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Remote access revoked'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _showGrantControlDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Remote Control Request'),
        content: const Text(
          'The caregiver wants to control your screen.\n\n'
          'They will be able to tap, swipe, and long press on your screen remotely.\n\n'
          'A floating button will appear — tap it anytime to revoke access.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              widget.webrtcService.revokeRemoteControl();
              Navigator.pop(ctx);
            },
            child: const Text('Deny', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2A7B62),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              // Check if accessibility service is enabled
              final enabled = await RemoteControlService.isAccessibilityEnabled();
              if (!enabled && mounted) {
                _showAccessibilitySetupDialog();
              } else {
                widget.webrtcService.grantRemoteControl();
              }
            },
            child: const Text('Grant Access', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showAccessibilitySetupDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enable Accessibility Service'),
        content: const Text(
          'To allow remote control, you need to enable the Remote Assist '
          'accessibility service.\n\n'
          '1. Tap "Open Settings" below\n'
          '2. Find "Remote Assist" in the list\n'
          '3. Turn it ON and tap Allow\n'
          '4. Return to this app',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2A7B62),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await RemoteControlService.openAccessibilitySettings();
              // When user returns, check again and grant if enabled
              _waitForAccessibilityService();
            },
            child: const Text('Open Settings', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _waitForAccessibilityService() {
    // Poll every 2 seconds to check if the user enabled the service
    Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final enabled = await RemoteControlService.isAccessibilityEnabled();
      if (enabled) {
        timer.cancel();
        widget.webrtcService.grantRemoteControl();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Remote control enabled!'),
              backgroundColor: Color(0xFF2A7B62),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    });
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

  // ─── PiP snap-to-corner logic ────────────────────────────────────────────

  /// Computes the default bottom-right position for the PiP window.
  Offset _defaultPipOffset(Size screenSize) {
    return Offset(
      screenSize.width - _pipWidth - _pipMargin,
      screenSize.height - _pipHeight - 160,
    );
  }

  /// Returns the nearest corner position for the PiP window.
  Offset _snapToCorner(Offset current, Size screenSize) {
    final double safeTop = MediaQuery.of(context).padding.top + _pipMargin;
    final double safeBottom = screenSize.height - _pipHeight - _pipMargin;
    final double left = _pipMargin;
    final double right = screenSize.width - _pipWidth - _pipMargin;

    final corners = [
      Offset(left, safeTop),          // top-left
      Offset(right, safeTop),         // top-right
      Offset(left, safeBottom),       // bottom-left
      Offset(right, safeBottom),      // bottom-right
    ];

    Offset nearest = corners.first;
    double minDist = double.infinity;
    for (final corner in corners) {
      final dist = (corner - current).distance;
      if (dist < minDist) {
        minDist = dist;
        nearest = corner;
      }
    }
    return nearest;
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    // Clean up floating button overlay
    if (_isElder) {
      RemoteControlService.hideFloatingButton();
      RemoteControlService.onFloatingButtonClicked = null;
    }
    widget.webrtcService.status.removeListener(_onStatusChanged);
    widget.webrtcService.localStream.removeListener(_onLocalStreamChanged);
    widget.webrtcService.remoteStream.removeListener(_onRemoteStreamChanged);
    widget.webrtcService.isScreenSharing.removeListener(_onScreenShareChanged);
    widget.webrtcService.isRemoteControlActive.removeListener(_onRemoteControlChanged);
    widget.webrtcService.remoteControlRequested.removeListener(_onControlRequested);
    widget.webrtcService.incomingTouch.removeListener(_onIncomingTouch);
    widget.webrtcService.incomingSwipe.removeListener(_onIncomingSwipe);
    widget.webrtcService.incomingLongPress.removeListener(_onIncomingLongPress);
    widget.webrtcService.incomingLongPressEnd.removeListener(_onIncomingLongPressEnd);
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  bool get _isElder => widget.role == 'elder';

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final status = widget.webrtcService.status.value;
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _resetControlsTimer,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Remote video (full-screen) ──────────────────────────────────
            _remoteRenderer.srcObject != null
                ? _buildRemoteVideoView()
                : _buildWaitingOverlay(status),

            // ── Draggable Local PiP ────────────────────────────────────────
            _buildDraggablePip(screenSize),

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

            // ── Screen share active banner (elder only) ─────────────────────
            if (_isScreenSharing && _isElder)
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

  /// Builds the draggable PiP widget that snaps to the nearest corner on release.
  Widget _buildDraggablePip(Size screenSize) {
    final offset = _pipOffset ?? _defaultPipOffset(screenSize);

    return AnimatedPositioned(
      duration: _isDraggingPip ? Duration.zero : const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      left: offset.dx,
      top: offset.dy,
      width: _pipWidth,
      height: _pipHeight,
      child: GestureDetector(
        // Tap PiP to switch camera (quick shortcut)
        onTap: _isElder && !_isScreenSharing ? _switchCamera : null,
        onPanStart: (_) => setState(() => _isDraggingPip = true),
        onPanUpdate: (details) {
          setState(() {
            final current = _pipOffset ?? _defaultPipOffset(screenSize);
            _pipOffset = Offset(
              (current.dx + details.delta.dx).clamp(0, screenSize.width - _pipWidth),
              (current.dy + details.delta.dy).clamp(0, screenSize.height - _pipHeight),
            );
          });
        },
        onPanEnd: (_) {
          setState(() {
            _isDraggingPip = false;
            _pipOffset = _snapToCorner(_pipOffset ?? _defaultPipOffset(screenSize), screenSize);
          });
        },
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
    );
  }

  /// Wraps the remote video view. When caregiver has remote control active,
  /// captures taps and swipes and sends them to the elder.
  Widget _buildRemoteVideoView() {
    final videoView = RTCVideoView(
      _remoteRenderer,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );

    // If caregiver and remote control is active, overlay a touch/swipe detector
    if (!_isElder && _isRemoteControlActive) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            // ── Tap detection ─────────────────────────────────────────
            onTapUp: (details) {
              final normX = details.localPosition.dx / constraints.maxWidth;
              final normY = details.localPosition.dy / constraints.maxHeight;
              widget.webrtcService.sendTouchEvent(
                normX.clamp(0.0, 1.0),
                normY.clamp(0.0, 1.0),
              );
              debugPrint('Remote tap: ($normX, $normY)');
            },
            // ── Long press detection ──────────────────────────────────
            onLongPressStart: (details) {
              final normX =
                  (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
              final normY =
                  (details.localPosition.dy / constraints.maxHeight).clamp(0.0, 1.0);
              widget.webrtcService.sendLongPressStartEvent(normX, normY);
              debugPrint('Remote long press START: ($normX, $normY)');
            },
            onLongPressEnd: (details) {
              widget.webrtcService.sendLongPressEndEvent();
              debugPrint('Remote long press END');
            },
            // ── Swipe detection ───────────────────────────────────────
            onPanStart: (details) {
              _swipeStartPosition = details.localPosition;
              _swipeStartTime = DateTime.now();
              _swipeEndPosition = details.localPosition;
            },
            onPanUpdate: (details) {
              _swipeEndPosition = details.localPosition;
            },
            onPanEnd: (details) {
              if (_swipeStartPosition != null &&
                  _swipeEndPosition != null &&
                  _swipeStartTime != null) {
                final durationMs = DateTime.now()
                    .difference(_swipeStartTime!)
                    .inMilliseconds;

                final startNormX =
                    (_swipeStartPosition!.dx / constraints.maxWidth).clamp(0.0, 1.0);
                final startNormY =
                    (_swipeStartPosition!.dy / constraints.maxHeight).clamp(0.0, 1.0);
                final endNormX =
                    (_swipeEndPosition!.dx / constraints.maxWidth).clamp(0.0, 1.0);
                final endNormY =
                    (_swipeEndPosition!.dy / constraints.maxHeight).clamp(0.0, 1.0);

                widget.webrtcService.sendSwipeEvent(
                  startNormX,
                  startNormY,
                  endNormX,
                  endNormY,
                  durationMs.clamp(50, 2000),
                );
                debugPrint(
                  'Remote swipe: ($startNormX,$startNormY) → ($endNormX,$endNormY) ${durationMs}ms',
                );
              }
              _swipeStartPosition = null;
              _swipeEndPosition = null;
              _swipeStartTime = null;
            },
            child: videoView,
          );
        },
      );
    }

    return videoView;
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
    // The caregiver sees the elder's screen share state via the data channel
    final elderIsScreenSharing = widget.webrtcService.isScreenSharing.value;

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
          // ── Caregiver secondary row (remote control button) ────────────
          // Only show when the remote video is present
          if (!_isElder && _remoteRenderer.srcObject != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ControlButton(
                    icon: _isRemoteControlActive ? Icons.cancel : Icons.touch_app,
                    color: _isRemoteControlActive
                        ? Colors.orange
                        : (elderIsScreenSharing ? Colors.white : Colors.white30),
                    backgroundColor: _isRemoteControlActive
                        ? Colors.orange.shade900.withAlpha(180)
                        : null,
                    label: _isRemoteControlActive
                        ? 'Stop Control'
                        : (elderIsScreenSharing ? 'Request Control' : 'Need Screen Share'),
                    onTap: () {
                      if (_isRemoteControlActive) {
                        widget.webrtcService.revokeRemoteControl();
                      } else if (elderIsScreenSharing) {
                        widget.webrtcService.requestRemoteControl();
                      } else {
                        // Screen share not active — show a hint
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('The elder must share their screen before you can request control.'),
                            backgroundColor: Colors.orange,
                            duration: Duration(seconds: 3),
                          ),
                        );
                      }
                    },
                    size: 44,
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
