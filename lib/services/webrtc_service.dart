import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_background/flutter_background.dart';

/// Manages a single WebRTC peer-to-peer call session.
/// Uses Firestore as the signaling channel (offer/answer/ICE candidates).
class WebRTCService {
  // ─── Public notifiers ────────────────────────────────────────────────────────

  ValueNotifier<MediaStream?> remoteStream = ValueNotifier(null);
  ValueNotifier<MediaStream?> localStream = ValueNotifier(null);
  ValueNotifier<CallStatus> status = ValueNotifier(CallStatus.idle);

  /// Set to the caregiver's name when they decline a call.
  ValueNotifier<String?> declineReason = ValueNotifier(null);

  /// Whether screen share is currently active (elder only).
  ValueNotifier<bool> isScreenSharing = ValueNotifier(false);

  /// Whether remote control is active.
  ValueNotifier<bool> isRemoteControlActive = ValueNotifier(false);

  /// Fires when caregiver requests control (elder sees this).
  ValueNotifier<bool> remoteControlRequested = ValueNotifier(false);

  /// Incoming touch event from caregiver: {"x": 0.0-1.0, "y": 0.0-1.0}
  ValueNotifier<Map<String, double>?> incomingTouch = ValueNotifier(null);

  /// Incoming swipe event from caregiver:
  /// {"startX", "startY", "endX", "endY": 0.0-1.0, "duration": ms}
  ValueNotifier<Map<String, double>?> incomingSwipe = ValueNotifier(null);

  /// Incoming long-press start event from caregiver: {"x", "y": 0.0-1.0}
  ValueNotifier<Map<String, double>?> incomingLongPress = ValueNotifier(null);

  /// Incoming drag update during a long press: {"x", "y": 0.0-1.0}
  ValueNotifier<Map<String, double>?> incomingDragUpdate = ValueNotifier(null);

  /// Fires when caregiver releases a long press / drag: {"x", "y": 0.0-1.0}
  ValueNotifier<Map<String, double>?> incomingDragEnd = ValueNotifier(null);

  // ─── Private state ──────────────────────────────────────────────────────────

  RTCPeerConnection? _pc;
  RTCDataChannel? _dataChannel;
  String? _currentCallId;
  bool _isFrontCamera = true;
  MediaStream? _screenShareStream;
  bool _isStartingScreenShare = false;
  bool _isMicEnabled = true; // tracks actual mic track state across stream refreshes

  static const _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ],
  };

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─── Camera / mic ───────────────────────────────────────────────────────────

  Future<void> _openLocalStream() async {
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': {
        'facingMode': 'user', // front camera default
        'width': {'ideal': 640},
        'height': {'ideal': 480},
      },
    });
    localStream.value = stream;
    _isFrontCamera = true;
  }

  // ─── Peer connection ────────────────────────────────────────────────────────

  Future<RTCPeerConnection> _createPC() async {
    final pc = await createPeerConnection(_iceServers);

    localStream.value?.getTracks().forEach((track) {
      pc.addTrack(track, localStream.value!);
    });

    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        debugPrint('WebRTCService: Remote track received');
        remoteStream.value = event.streams.first;
      }
    };

    pc.onConnectionState = (state) {
      debugPrint('WebRTCService: Connection state → $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        status.value = CallStatus.connected;
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        if (!_isStartingScreenShare) status.value = CallStatus.ended;
      }
    };

    pc.onIceConnectionState = (state) {
      debugPrint('WebRTCService: ICE Connection state → $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        status.value = CallStatus.connected;
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        debugPrint('WebRTCService: ICE disconnected – attempting restart');
        _pc?.restartIce();
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        if (!_isStartingScreenShare) status.value = CallStatus.ended;
      }
    };

    // Listen for data channel created by the remote peer (caregiver side)
    pc.onDataChannel = (channel) {
      debugPrint('WebRTCService: Data channel received: ${channel.label}');
      _dataChannel = channel;
      _setupDataChannelListeners();
    };

    return pc;
  }

  /// Setup listeners on the data channel for remote control messages.
  void _setupDataChannelListeners() {
    _dataChannel?.onMessage = (message) {
      try {
        final data = jsonDecode(message.text) as Map<String, dynamic>;
        final type = data['type'] as String?;

        switch (type) {
          case 'touch':
            // Caregiver sent a touch event → elder processes it
            if (isRemoteControlActive.value) {
              incomingTouch.value = {
                'x': (data['x'] as num).toDouble(),
                'y': (data['y'] as num).toDouble(),
              };
            }
            break;
          case 'swipe':
            // Caregiver sent a swipe event → elder processes it
            if (isRemoteControlActive.value) {
              incomingSwipe.value = {
                'startX': (data['startX'] as num).toDouble(),
                'startY': (data['startY'] as num).toDouble(),
                'endX': (data['endX'] as num).toDouble(),
                'endY': (data['endY'] as num).toDouble(),
                'duration': (data['duration'] as num).toDouble(),
              };
            }
            break;
          case 'longPressStart':
            // Caregiver started a long press → elder starts continued gesture
            if (isRemoteControlActive.value) {
              incomingLongPress.value = {
                'x': (data['x'] as num).toDouble(),
                'y': (data['y'] as num).toDouble(),
              };
            }
            break;
          case 'dragUpdate':
            // Caregiver is dragging during a long press → elder continues gesture
            if (isRemoteControlActive.value) {
              incomingDragUpdate.value = {
                'x': (data['x'] as num).toDouble(),
                'y': (data['y'] as num).toDouble(),
              };
            }
            break;
          case 'longPressEnd':
            // Caregiver released the long press / drag → elder lifts finger
            if (isRemoteControlActive.value) {
              incomingDragEnd.value = {
                'x': (data['x'] as num).toDouble(),
                'y': (data['y'] as num).toDouble(),
              };
            }
            break;
          case 'requestControl':
            // Caregiver is requesting control → elder sees prompt
            debugPrint('WebRTCService: Remote control requested');
            remoteControlRequested.value = true;
            break;
          case 'grantControl':
            // Elder granted control → caregiver can now send touches
            debugPrint('WebRTCService: Remote control granted');
            isRemoteControlActive.value = true;
            break;
          case 'revokeControl':
            // Either side revoked control
            debugPrint('WebRTCService: Remote control revoked');
            isRemoteControlActive.value = false;
            remoteControlRequested.value = false;
            break;
          case 'screenShareStarted':
            // Elder started screen share → caregiver updates its local state
            debugPrint('WebRTCService: Remote peer started screen share');
            isScreenSharing.value = true;
            break;
          case 'screenShareStopped':
            // Elder stopped screen share → caregiver updates its local state
            debugPrint('WebRTCService: Remote peer stopped screen share');
            isScreenSharing.value = false;
            break;
        }
      } catch (e) {
        debugPrint('WebRTCService: Error parsing data channel message: $e');
      }
    };

    _dataChannel?.onDataChannelState = (state) {
      debugPrint('WebRTCService: Data channel state → $state');
    };
  }

  void _listenAndUploadICE(String callId, String side) {
    _pc!.onIceCandidate = (candidate) {
      if (candidate.candidate != null && candidate.candidate!.isNotEmpty) {
        _db.collection('calls').doc(callId).collection(side).add(candidate.toMap());
      }
    };
  }

  void _listenForRemoteICE(String callId, String remoteSide) {
    _db.collection('calls').doc(callId).collection(remoteSide).snapshots().listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data()!;
          if (data['candidate'] != null && data['candidate'].toString().isNotEmpty) {
            final candidate = RTCIceCandidate(
              data['candidate'],
              data['sdpMid'],
              data['sdpMLineIndex'],
            );
            _pc?.addCandidate(candidate);
          }
        }
      }
    });
  }

  // ─── Public API ─────────────────────────────────────────────────────────────

  /// Called by the **elder**: opens camera, creates offer, writes to Firestore.
  Future<String> startCallAsElder(String elderId) async {
    status.value = CallStatus.waiting;
    declineReason.value = null;

    await _openLocalStream();
    _pc = await _createPC();

    // Create the data channel (elder is the offerer, so it creates the channel)
    _dataChannel = await _pc!.createDataChannel(
      'remote_control',
      RTCDataChannelInit()..ordered = true,
    );
    _setupDataChannelListeners();

    final callRef = _db.collection('calls').doc();
    _currentCallId = callRef.id;

    _listenAndUploadICE(_currentCallId!, 'offerCandidates');

    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);

    await callRef.set({
      'elderId': elderId,
      'offer': {'type': offer.type, 'sdp': offer.sdp},
      'status': 'waiting',
      'createdAt': FieldValue.serverTimestamp(),
    });

    debugPrint('WebRTCService: Offer created. callId=$_currentCallId');

    // Listen for answer & status changes from caregiver
    callRef.snapshots().listen((snapshot) async {
      if (!snapshot.exists) return;
      final data = snapshot.data()!;

      // Caregiver answered
      if (data['answer'] != null &&
          _pc?.signalingState != RTCSignalingState.RTCSignalingStateStable) {
        final answerData = data['answer'] as Map<String, dynamic>;
        final answer = RTCSessionDescription(answerData['sdp'], answerData['type']);
        await _pc!.setRemoteDescription(answer);
        debugPrint('WebRTCService: Remote answer set.');
        status.value = CallStatus.connecting;
        
        // Now that remote description is set, safe to add candidates
        _listenForRemoteICE(_currentCallId!, 'answerCandidates');
      }

      // Caregiver declined → set reason then end without writing 'ended' back
      if (data['status'] == 'declined') {
        final name = data['declinedByName'] as String? ?? 'Caregiver';
        declineReason.value = name;
        _dispose();
        status.value = CallStatus.ended;
      } else if (data['status'] == 'ended') {
        await hangUp();
      }
    });

    return _currentCallId!;
  }

  /// Called by the **caregiver**: reads offer, creates answer, writes back.
  Future<void> answerCallAsCaregiver(String callId, String caregiverId) async {
    status.value = CallStatus.connecting;
    _currentCallId = callId;

    await _openLocalStream();
    _pc = await _createPC();

    _listenAndUploadICE(callId, 'answerCandidates');

    final callRef = _db.collection('calls').doc(callId);
    final callSnapshot = await callRef.get();
    final offerData = callSnapshot.data()!['offer'] as Map<String, dynamic>;

    final offer = RTCSessionDescription(offerData['sdp'], offerData['type']);
    await _pc!.setRemoteDescription(offer);

    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);

    await callRef.update({
      'answer': {'type': answer.type, 'sdp': answer.sdp},
      'caregiverId': caregiverId,
      'status': 'active',
    });

    debugPrint('WebRTCService: Answer sent. callId=$callId');

    callRef.snapshots().listen((snapshot) async {
      if (!snapshot.exists) return;
      final data = snapshot.data()!;
      if (data['status'] == 'ended') {
        await hangUp();
      }
    });

    _listenForRemoteICE(callId, 'offerCandidates');
  }

  // ─── Media controls ──────────────────────────────────────────────────────────

  Future<void> toggleMic() async {
    final audioTracks = localStream.value?.getAudioTracks() ?? [];
    for (final track in audioTracks) {
      track.enabled = !track.enabled;
    }
    // Keep our internal mic tracker in sync
    if (audioTracks.isNotEmpty) {
      _isMicEnabled = audioTracks.first.enabled;
    }
  }

  Future<void> toggleCamera() async {
    final videoTracks = localStream.value?.getVideoTracks() ?? [];
    for (final track in videoTracks) {
      track.enabled = !track.enabled;
    }
  }

  /// Flips between front and back camera.
  Future<void> switchCamera() async {
    if (isScreenSharing.value) return;
    final videoTracks = localStream.value?.getVideoTracks() ?? [];
    if (videoTracks.isNotEmpty) {
      await Helper.switchCamera(videoTracks.first);
      _isFrontCamera = !_isFrontCamera;
    }
  }

  // ─── Screen share (elder) ────────────────────────────────────────────────────

  Future<void> toggleScreenShare() async {
    if (isScreenSharing.value) {
      await _stopScreenShare();
    } else {
      await _startScreenShare();
    }
  }

  Future<void> _startScreenShare() async {
    // Guard: prevents transient ICE disconnections during the MediaProjection
    // permission dialog (which briefly backgrounds the app) from ending the call.
    _isStartingScreenShare = true;
    try {
      // On Android 10+, the OS requires a running foreground service before the
      // MediaProjection permission result returns (app is briefly backgrounded).
      // We use flutter_background to start one BEFORE calling getDisplayMedia().
      // flutter_webrtc's own MediaProjectionService then takes over for the capture.
      const androidConfig = FlutterBackgroundAndroidConfig(
        notificationTitle: 'Screen Sharing',
        notificationText: 'Remote Assist is sharing your screen',
        notificationImportance: AndroidNotificationImportance.Default,
        enableWifiLock: false,
      );
      final hasPermission =
          await FlutterBackground.initialize(androidConfig: androidConfig);
      if (hasPermission) {
        await FlutterBackground.enableBackgroundExecution();
      }

      _screenShareStream = await navigator.mediaDevices.getDisplayMedia({
        'audio': false,
        'video': true,
      });

      final screenTrack = _screenShareStream!.getVideoTracks().first;

      // Replace the video sender's track in the peer connection
      if (_pc != null) {
        final senders = await _pc!.getSenders();
        for (final sender in senders) {
          if (sender.track?.kind == 'video') {
            await sender.replaceTrack(screenTrack);
            break;
          }
        }
      }

      // Replace the video track in the local stream so PiP shows the screen
      if (localStream.value != null) {
        for (final t in localStream.value!.getVideoTracks().toList()) {
          await localStream.value!.removeTrack(t);
        }
        await localStream.value!.addTrack(screenTrack);
      }

      // Poke the notifier so renderers refresh
      final s = localStream.value;
      localStream.value = null;
      localStream.value = s;

      isScreenSharing.value = true;
      // Notify the remote peer (caregiver) that screen share started
      _sendDataChannelMessage({'type': 'screenShareStarted'});
      debugPrint('WebRTCService: Screen share started');

      // If user stops share via the OS system UI, auto-restore camera
      screenTrack.onEnded = () async => _stopScreenShare();
    } catch (e) {
      debugPrint('WebRTCService: Screen share error: $e');
      rethrow;
    } finally {
      _isStartingScreenShare = false;
    }
  }

  Future<void> _stopScreenShare() async {
    try {
      // Auto-revoke remote control when screen share ends
      if (isRemoteControlActive.value) {
        revokeRemoteControl();
      }

      // Stop the keep-alive foreground service now that screen share is ending.
      if (FlutterBackground.isBackgroundExecutionEnabled) {
        await FlutterBackground.disableBackgroundExecution();
      }
      _screenShareStream?.getTracks().forEach((t) => t.stop());
      _screenShareStream?.dispose();
      _screenShareStream = null;

      // Get a completely fresh camera+audio stream.
      // This gives us a NEW MediaStream object so the renderer fully re-attaches.
      final freshStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {
          'facingMode': _isFrontCamera ? 'user' : 'environment',
          'width': {'ideal': 640},
          'height': {'ideal': 480},
        },
      });

      final cameraTrack = freshStream.getVideoTracks().first;

      // Restore the mic enabled state from before screen share
      // (getUserMedia always creates tracks with enabled=true)
      final freshAudio = freshStream.getAudioTracks().first;
      freshAudio.enabled = _isMicEnabled;

      // Replace the video sender's track in the peer connection
      if (_pc != null) {
        final senders = await _pc!.getSenders();
        for (final sender in senders) {
          if (sender.track?.kind == 'video') {
            await sender.replaceTrack(cameraTrack);
            break;
          }
        }
        // Also replace the audio sender so toggleMic works on the new tracks
        for (final sender in senders) {
          if (sender.track?.kind == 'audio') {
            await sender.replaceTrack(freshAudio);
            break;
          }
        }
      }

      // Stop old local stream tracks and dispose
      localStream.value?.getTracks().forEach((t) => t.stop());

      // Set the brand new stream — new object reference forces renderer refresh
      localStream.value = freshStream;

      // Notify the remote peer (caregiver) that screen share stopped
      _sendDataChannelMessage({'type': 'screenShareStopped'});

      debugPrint('WebRTCService: Screen share stopped, camera restored');
    } catch (e) {
      debugPrint('WebRTCService: Stop screen share error: $e');
    } finally {
      isScreenSharing.value = false;
    }
  }

  // ─── Remote control ──────────────────────────────────────────────────────────

  /// Caregiver calls this to request control of the elder's screen.
  void requestRemoteControl() {
    _sendDataChannelMessage({'type': 'requestControl'});
    debugPrint('WebRTCService: Sent control request');
  }

  /// Elder calls this to grant control to the caregiver.
  void grantRemoteControl() {
    remoteControlRequested.value = false;
    isRemoteControlActive.value = true;
    _sendDataChannelMessage({'type': 'grantControl'});
    debugPrint('WebRTCService: Granted remote control');
  }

  /// Either side calls this to revoke remote control.
  void revokeRemoteControl() {
    isRemoteControlActive.value = false;
    remoteControlRequested.value = false;
    _sendDataChannelMessage({'type': 'revokeControl'});
    debugPrint('WebRTCService: Revoked remote control');
  }

  /// Caregiver calls this to send a tap event to the elder.
  void sendTouchEvent(double normX, double normY) {
    if (!isRemoteControlActive.value) return;
    _sendDataChannelMessage({
      'type': 'touch',
      'x': normX,
      'y': normY,
    });
  }

  /// Caregiver calls this to send a swipe event to the elder.
  void sendSwipeEvent(
    double startX, double startY,
    double endX, double endY,
    int durationMs,
  ) {
    if (!isRemoteControlActive.value) return;
    _sendDataChannelMessage({
      'type': 'swipe',
      'startX': startX,
      'startY': startY,
      'endX': endX,
      'endY': endY,
      'duration': durationMs,
    });
  }

  /// Caregiver calls this when they start a long press.
  void sendLongPressStartEvent(double normX, double normY) {
    if (!isRemoteControlActive.value) return;
    _sendDataChannelMessage({
      'type': 'longPressStart',
      'x': normX,
      'y': normY,
    });
  }

  /// Caregiver calls this when they drag during a long press.
  void sendDragUpdateEvent(double normX, double normY) {
    if (!isRemoteControlActive.value) return;
    _sendDataChannelMessage({
      'type': 'dragUpdate',
      'x': normX,
      'y': normY,
    });
  }

  /// Caregiver calls this when they release a long press / drag.
  void sendLongPressEndEvent(double normX, double normY) {
    if (!isRemoteControlActive.value) return;
    _sendDataChannelMessage({
      'type': 'longPressEnd',
      'x': normX,
      'y': normY,
    });
  }

  void _sendDataChannelMessage(Map<String, dynamic> data) {
    if (_dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen) {
      _dataChannel!.send(RTCDataChannelMessage(jsonEncode(data)));
    } else {
      debugPrint('WebRTCService: Data channel not open, cannot send message');
    }
  }

  // ─── Lifecycle ───────────────────────────────────────────────────────────────

  Future<void> hangUp() async {
    if (_currentCallId != null) {
      try {
        await _db.collection('calls').doc(_currentCallId).update({'status': 'ended'});
      } catch (_) {}
    }
    _dispose();
    status.value = CallStatus.ended;
  }

  void _dispose() {
    _screenShareStream?.getTracks().forEach((t) => t.stop());
    _screenShareStream?.dispose();
    _screenShareStream = null;

    localStream.value?.getTracks().forEach((t) => t.stop());
    localStream.value?.dispose();
    localStream.value = null;

    remoteStream.value?.dispose();
    remoteStream.value = null;

    _dataChannel?.close();
    _dataChannel = null;

    isRemoteControlActive.value = false;
    remoteControlRequested.value = false;
    incomingSwipe.value = null;
    incomingLongPress.value = null;
    incomingDragUpdate.value = null;
    incomingDragEnd.value = null;

    _pc?.close();
    _pc = null;
    _currentCallId = null;
  }
}

enum CallStatus { idle, waiting, connecting, connected, ended }
