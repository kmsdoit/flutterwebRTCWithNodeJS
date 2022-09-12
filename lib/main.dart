import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {

  late final IO.Socket socket;
  final _localRenderer = RTCVideoRenderer(); // 내 얼굴
  final _remoteRenderer = RTCVideoRenderer(); // 상대방 얼굴
  MediaStream? _localStream; // 보이스와 실제로 들어오는 데이터들
  RTCPeerConnection? pc; // 상대방과 통신하기 위해 필요한 객체

  @override
  void initState() {
    // TODO: implement initState
    init();
    super.initState();
  }

  Future init() async{
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    await connectSocket();
    await joinRoom();
  }

  Future connectSocket() async{
    socket = IO.io("http://localhost:3000", IO.OptionBuilder().setTransports(['websocket']).build());
    socket.onConnect((data) => print('연결 완료'));

    socket.on('joined', (data) {
      _sendOffer();
    });

    socket.on('offer', (data) async{
      data = jsonDecode(data);
      await _getOffer(RTCSessionDescription(data["sdp"], data["type"]));
      await _sendAnswer();
    });

    socket.on('answer', (data){
      data = jsonDecode(data);
      _getAnswer(RTCSessionDescription(data["sdp"], data["type"]));
    });

    socket.on('ice', (data) {
      data = jsonDecode(data);
      _getIce(RTCIceCandidate(data['candidate'], data['sdpMid'], data['sdpMLineIndex']));
    });
  }

  Future joinRoom() async{
    final config = {
      'iceServers' : [
        {"url":"stun:stun.l.google.com:19302"}
      ]
    };

    final sdpConstraints = {
      'mandatory':{
        'OfferToReceiveAudio':true,
        'OfferToReceiveVideo':true
      },
      'optional': []
    };

    pc = await createPeerConnection(config,sdpConstraints);

    final mediaConstraints = {
      'audio': true,
      'video': {
        'facingMode':'user'
      }
    };

    _localStream = await Helper.openCamera(mediaConstraints);

    _localStream!.getTracks().forEach((track) {
      pc!.addTrack(track,_localStream!);
     });  

     _localRenderer.srcObject = _localStream;

     pc!.onIceCandidate = (ice) {
      // ice를 상대방에게 보내주면 됩니다
      _sendIce(ice);
     };

     pc!.onAddStream = (stream) {
      _remoteRenderer.srcObject = stream;
     };

     socket.emit('join');

  }

  Future _sendOffer() async {
    print('send offer');
    var offer = await pc!.createOffer();
    pc!.setLocalDescription(offer);
    socket.emit('offer', jsonEncode(offer.toMap()));
  }

  Future _getOffer(RTCSessionDescription offer) async {
    print('get offer');
    pc!.setRemoteDescription(offer);
  }

  Future _sendAnswer() async {
    print('send answer');
    var answer = await pc!.createAnswer();
    pc!.setLocalDescription(answer);
    socket.emit('answer', jsonEncode(answer.toMap()));
  }

  Future _getAnswer(RTCSessionDescription answer) async {
    print('get answer');
    pc!.setRemoteDescription(answer);
  }

  Future _sendIce(RTCIceCandidate ice) async {
    print('send ice');
    socket.emit('ice', jsonEncode(ice.toMap()));
  }

  Future _getIce(RTCIceCandidate ice) async {
    print('get ice');
    pc!.addCandidate(ice);
  }




  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Row(
        children: [
          Expanded(child: RTCVideoView(_localRenderer)),
          Expanded(child: RTCVideoView(_remoteRenderer))
        ],
        )
    );
  }
}