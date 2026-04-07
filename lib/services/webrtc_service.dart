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

  // ─── Private state ──────────────────────────────────────────────────────────

  RTCPeerConnection? _pc;
  String? _currentCallId;
  bool _isFrontCamera = true;
  MediaStream? _screenShareStream;

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
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        status.value = CallStatus.ended;
      }
    };

    pc.onIceConnectionState = (state) {
      debugPrint('WebRTCService: ICE Connection state → $state');
      // Some platforms fire ICE connection state reliably instead of PC connection state.
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        status.value = CallStatus.connected;
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        status.value = CallStatus.ended;
      }
    };

    return pc;
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
    try {
      // 1. Initialize and start a foreground service for MediaProjection
      const androidConfig = FlutterBackgroundAndroidConfig(
        notificationTitle: 'Screen Sharing',
        notificationText: 'Remote Assist is capturing your screen',
        notificationImportance: AndroidNotificationImportance.Default,
        enableWifiLock: true,
      );
      bool hasPermissions = await FlutterBackground.initialize(androidConfig: androidConfig);
      if (hasPermissions) {
        await FlutterBackground.enableBackgroundExecution();
      }

      // 2. Request the system screen recording permission dialog
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
        for (final t in localStream.value!.getVideoTracks()) {
          await localStream.value!.removeTrack(t);
        }
        await localStream.value!.addTrack(screenTrack);
      }

      // Poke the notifier so renderers refresh
      final s = localStream.value;
      localStream.value = null;
      localStream.value = s;

      isScreenSharing.value = true;
      debugPrint('WebRTCService: Screen share started');

      // If user stops share via the OS system UI, auto-restore camera
      screenTrack.onEnded = () async => _stopScreenShare();
    } catch (e) {
      debugPrint('WebRTCService: Screen share error: $e');
      rethrow;
    }
  }

  Future<void> _stopScreenShare() async {
    try {
      // Disable flutter_background immediately
      if (FlutterBackground.isBackgroundExecutionEnabled) {
        await FlutterBackground.disableBackgroundExecution();
      }

      _screenShareStream?.getTracks().forEach((t) => t.stop());
      _screenShareStream?.dispose();
      _screenShareStream = null;

      // Get a fresh camera track to restore
      final cameraStream = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {'facingMode': _isFrontCamera ? 'user' : 'environment'},
      });
      final cameraTrack = cameraStream.getVideoTracks().first;

      // Replace sender track back to camera
      if (_pc != null) {
        final senders = await _pc!.getSenders();
        for (final sender in senders) {
          if (sender.track?.kind == 'video') {
            await sender.replaceTrack(cameraTrack);
            break;
          }
        }
      }

      // Restore local stream video track
      if (localStream.value != null) {
        for (final t in localStream.value!.getVideoTracks()) {
          await localStream.value!.removeTrack(t);
          t.stop();
        }
        await localStream.value!.addTrack(cameraTrack);
      }

      // Poke the notifier
      final s = localStream.value;
      localStream.value = null;
      localStream.value = s;

      isScreenSharing.value = false;
      debugPrint('WebRTCService: Screen share stopped, camera restored');
    } catch (e) {
      debugPrint('WebRTCService: Stop screen share error: $e');
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

    _pc?.close();
    _pc = null;
    _currentCallId = null;
  }
}

enum CallStatus { idle, waiting, connecting, connected, ended }
