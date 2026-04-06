import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


/// Manages a single WebRTC peer-to-peer call session.
/// Uses Firestore as the signaling channel (offer/answer/ICE candidates).
class WebRTCService {
  // ─── Public streams / notifiers ────────────────────────────────────────────

  /// Fires whenever the remote stream is received from the peer.
  ValueNotifier<MediaStream?> remoteStream = ValueNotifier(null);

  /// Fires whenever the local camera stream is ready.
  ValueNotifier<MediaStream?> localStream = ValueNotifier(null);

  /// Call status for the UI to react to.
  ValueNotifier<CallStatus> status = ValueNotifier(CallStatus.idle);

  // ─── Private state ──────────────────────────────────────────────────────────

  RTCPeerConnection? _pc;
  String? _currentCallId;

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
        'facingMode': 'user',
        'width': {'ideal': 640},
        'height': {'ideal': 480},
      },
    });
    localStream.value = stream;
  }

  // ─── Peer connection ────────────────────────────────────────────────────────

  Future<RTCPeerConnection> _createPC() async {
    final pc = await createPeerConnection(_iceServers);

    // Add local tracks to the connection
    localStream.value?.getTracks().forEach((track) {
      pc.addTrack(track, localStream.value!);
    });

    // Remote stream handling
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

    return pc;
  }

  /// Push local ICE candidates to Firestore under [side] subcollection.
  void _listenAndUploadICE(String callId, String side) {
    _pc!.onIceCandidate = (candidate) {
      _db
          .collection('calls')
          .doc(callId)
          .collection(side)
          .add(candidate.toMap());
    };
  }

  /// Subscribe to remote ICE candidates from Firestore and add them to the PC.
  void _listenForRemoteICE(String callId, String remoteSide) {
    _db
        .collection('calls')
        .doc(callId)
        .collection(remoteSide)
        .snapshots()
        .listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data()!;
          final candidate = RTCIceCandidate(
            data['candidate'],
            data['sdpMid'],
            data['sdpMLineIndex'],
          );
          _pc?.addCandidate(candidate);
        }
      }
    });
  }

  // ─── Public API ─────────────────────────────────────────────────────────────

  /// Called by the **elder**: opens camera, creates offer, writes to Firestore.
  /// Returns the [callId] so the elder can navigate to CallScreen.
  Future<String> startCallAsElder(String elderId) async {
    status.value = CallStatus.waiting;

    await _openLocalStream();
    _pc = await _createPC();

    // Create Firestore call document
    final callRef = _db.collection('calls').doc();
    _currentCallId = callRef.id;

    // Upload elder's ICE candidates
    _listenAndUploadICE(_currentCallId!, 'offerCandidates');

    // Create SDP offer
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);

    await callRef.set({
      'elderId': elderId,
      'offer': {'type': offer.type, 'sdp': offer.sdp},
      'status': 'waiting',
      'createdAt': FieldValue.serverTimestamp(),
    });

    debugPrint('WebRTCService: Offer created. callId=$_currentCallId');

    // Listen for caregiver's answer
    callRef.snapshots().listen((snapshot) async {
      if (!snapshot.exists) return;
      final data = snapshot.data()!;

      if (data['answer'] != null &&
          _pc!.signalingState !=
              RTCSignalingState.RTCSignalingStateStable) {
        final answerData = data['answer'] as Map<String, dynamic>;
        final answer = RTCSessionDescription(
          answerData['sdp'],
          answerData['type'],
        );
        await _pc!.setRemoteDescription(answer);
        debugPrint('WebRTCService: Remote answer set.');
        status.value = CallStatus.connecting;
      }

      if (data['status'] == 'ended') {
        await hangUp();
      }
    });

    // Listen for caregiver's ICE candidates
    _listenForRemoteICE(_currentCallId!, 'answerCandidates');

    return _currentCallId!;
  }

  /// Called by the **caregiver**: reads offer, creates answer, writes back.
  Future<void> answerCallAsCaregiver(String callId, String caregiverId) async {
    status.value = CallStatus.connecting;
    _currentCallId = callId;

    await _openLocalStream();
    _pc = await _createPC();

    // Upload caregiver's ICE candidates
    _listenAndUploadICE(callId, 'answerCandidates');

    // Read offer
    final callRef = _db.collection('calls').doc(callId);
    final callSnapshot = await callRef.get();
    final offerData = callSnapshot.data()!['offer'] as Map<String, dynamic>;

    final offer =
        RTCSessionDescription(offerData['sdp'], offerData['type']);
    await _pc!.setRemoteDescription(offer);

    // Create answer
    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);

    // Write answer + caregiverId back to Firestore
    await callRef.update({
      'answer': {'type': answer.type, 'sdp': answer.sdp},
      'caregiverId': caregiverId,
      'status': 'active',
    });

    debugPrint('WebRTCService: Answer sent. callId=$callId');

    // Listen for call end
    callRef.snapshots().listen((snapshot) async {
      if (!snapshot.exists) return;
      final data = snapshot.data()!;
      if (data['status'] == 'ended') {
        await hangUp();
      }
    });

    // Listen for elder's ICE candidates
    _listenForRemoteICE(callId, 'offerCandidates');
  }

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

  Future<void> switchCamera() async {
    final videoTracks = localStream.value?.getVideoTracks() ?? [];
    if (videoTracks.isNotEmpty) {
      await Helper.switchCamera(videoTracks.first);
    }
  }

  Future<void> hangUp() async {
    if (_currentCallId != null) {
      try {
        await _db
            .collection('calls')
            .doc(_currentCallId)
            .update({'status': 'ended'});
      } catch (_) {}
    }
    _dispose();
    status.value = CallStatus.ended;
  }

  void _dispose() {
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
