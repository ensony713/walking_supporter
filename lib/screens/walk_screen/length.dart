import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import 'package:walking_googlemap/screens/diary.dart';
import 'package:walking_googlemap/DB/Recode.dart';
import 'package:walking_googlemap/class/LocationManager.dart';

class Length extends StatefulWidget {
  const Length({Key? key}) : super(key: key);

  @override
  _LengthState createState() => _LengthState();
}

class _LengthState extends State<Length> {
  late TextEditingController _destinationController; // 입력 처리 컨트롤러
  late TextEditingController _diaryController;
  late GoogleMapController _mapController; // 지도 컨트롤러

  static const CameraPosition _kGooglePlex = CameraPosition( // 카메라 초기 위치
    target: LatLng(37.011289, 127.265021),
    zoom: 10.0,
  );

  LocationManager lm = LocationManager();

  final List<Marker> _markers = []; // 마커 배열
  late BitmapDescriptor _markerIcon; // 현재 위치를 나타낼 아이콘
  late Marker _currentMarker; // 현재 위치 마커
  late Marker startPoint; // 시작지점 마커
  late Marker _destinationPoint = const Marker(markerId: MarkerId("non")); // 목적지 마커

  List<LatLng> _track = []; // 이동 경로를 저장할 배열
  Map<PolylineId, Polyline> _polylines = <PolylineId, Polyline>{ };

  int _length = 0; // 오늘 산책한 총 이동 거리
  int _startLength = 0; // 산책 시작했을 때 이동 거리
  int _walkingLength = 0; // 목적지까지 남은 잔여 거리
  String date = ""; // DB date
  String day = '';

  bool _isWalking = false; // 산책 중인지 아닌지, 산책 중이면 true.
  bool _moveMode = false;

  String getDate() {
    DateTime now = DateTime.now();
    DateFormat format = DateFormat('yyyy/MM/dd');
    date = format.format(now);

    DateFormat dateFormat = DateFormat('yyyy년 MM월 dd일');
    day = dateFormat.format(now);
    return date;
  }

  void setIcon() async {
    _markerIcon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(devicePixelRatio: 2.5),
        'images/icons/putprint_pin.png');
  }

  void getDB() async {
    Recode recode = await getDateRecode(date);
    _length = recode.length;
  }

  @override
  void initState() {
    super.initState();
    _destinationController = TextEditingController();
    _diaryController = TextEditingController();
    getDate(); // 오늘 날짜를 받아올 메소드, 이후 저장 전 등에 다시 호출되어야.
    setIcon(); // 현재 위치 아이콘 지정 메소드
    getLocation(); // 일회적으로 위치를 받아오는 메소드, 첫 실행 시 한 번만 수행할 예정
    asyncGetLocation(); // 실시간 위치 정보 갱신 메소드
    getDB();
  }

  @override
  void dispose() {
    _diaryController.dispose();
    _destinationController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deviceWidth = MediaQuery.of(context).size.width;
    final deviceHeight = MediaQuery.of(context).size.height;
    final deviceArea = deviceHeight * deviceWidth;

    return GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(deviceWidth * 0.08, deviceHeight * 0.01, deviceWidth * 0.08, deviceHeight * 0.005),
                child: TextField(controller: _destinationController, // 목적지 입력 필드
                  onSubmitted: _inputDestination,
                  decoration: const InputDecoration(
                      labelText: '목적지',
                      hintText: '이곳에 목적지를 입력해주세요',
                      labelStyle: TextStyle(color: Colors.lightGreen),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(10.0)),
                          borderSide: BorderSide(
                              width: 1, color: Colors.lightGreen)
                      ),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(10.0)),
                          borderSide: BorderSide(
                              width: 1, color: Colors.lightGreen)
                      ),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(10.0))
                      )
                  ),
                ),
              ),
              Container( // 구글 지도
                width: deviceWidth * 0.95,
                height: deviceHeight * 0.5,
                //color: Colors.lightGreen,
                child: GoogleMap(
                  onMapCreated: (controller) {
                    setState(() {
                      _mapController = controller;
                    });
                    _currentMarker = Marker(markerId: const MarkerId("now"),
                      position: lm.now,
                      icon: _markerIcon,
                    );
                  },
                  mapType: MapType.normal,
                  initialCameraPosition: _kGooglePlex,
                  onCameraMove: (_) {},
                  myLocationButtonEnabled: false,
                  markers: _markers.toSet(),
                  polylines: Set<Polyline>.of(_polylines.values),
                  onTap: (chosen) {
                    if(!_isWalking && !_moveMode) { // 산책 중이 아닐 때만 탭한 위치에 마커 추가
                      _addDestination(chosen);
                    } else {
                      _mapController.animateCamera(CameraUpdate.newLatLng(chosen));
                    }
                    // 산책 중일 땐 지도에 들어오는 터치 무시
                  },
                ),
              ),
              Row(children: [
                TextButton(
                  onPressed: () {
                    setState((){
                      _moveMode = !_moveMode;
                    });
                  },
                  child: _moveMode ? const Text("지도 이동") : const Text("목적지 선택"),
                  style: TextButton.styleFrom(
                      backgroundColor: _moveMode ? Colors.lightGreen : Colors.redAccent,
                      primary: Colors.black
                  ),
                ),
                SizedBox(width: deviceWidth * 0.03,),
                Column( children:[ // 산책 거리를 보여줄 위젯
                  Text('총 산책 거리 ${_length}m'),
                  Text('목적지까지의 거리 ${_walkingLength}m'),
                ]),
                SizedBox(width: deviceWidth * 0.03,),
                TextButton( // 길 안내 시작 / 산책 완료 버튼 위젯
                  onPressed: () async {
                    if (_isWalking) { // 산책 중일 때

                      // 목적지까지의 거리 0으로 초기화
                      _walkingLength = 0;

                      if (_length - _startLength != 0) {
                        // 산책 완료를 눌렀을 때 이동한 거리가 0m가 아니라면, DB에 저장
                        await updateLength(date, _length);

                        // 일기를 쓸지 질의하는 창 띄우기
                        askMakeDiary(context);
                      }

                      // 지도에서 목적지 마커 삭제
                      setState((){
                        _markers.remove(_destinationPoint);
                        _isWalking = false;
                      });

                      // startPoint랑 _destinationPoint 초기화
                      startPoint = const Marker(markerId: MarkerId("non"));
                      _destinationPoint = const Marker(markerId: MarkerId("non"));

                      _track = []; // 이동 경로 초기화
                      _polylines = <PolylineId, Polyline>{};

                    } else { // 산책 중이 아닐 때

                      // 이번 산책에서 진행한 거리를 알기 위한 변수 저장
                      _startLength = _length;

                      if (_destinationPoint.markerId != const MarkerId('non')) {
                        // 시작지점 저장
                        startPoint = Marker(markerId: const MarkerId("start"),
                          position: lm.now,
                        );
                        _track.add(startPoint.position);

                        // 이동한 경로를 기록해 지도에 띄우기 시작
                        Polyline line = Polyline(polylineId: const PolylineId(
                            'walking tracker'),
                          color: Colors.green,
                          points: _track,
                          width: 7,
                        );
                        _polylines[const PolylineId('track')] = line;

                        setState(() { // 산책 상태 갱신
                          _isWalking = true;
                        });
                      } else {
                        // 목적지를 선택해달라는 알림 창을 띄움
                        _plzChooseDestination(context);
                      }
                    }
                  },
                  child: _isWalking ? const Text("산책 완료") : const Text("산책 시작"),
                  style: TextButton.styleFrom(
                    textStyle: TextStyle(fontSize: deviceArea * 0.00005),
                    primary: Colors.black,
                    backgroundColor: _isWalking ? Colors.green : Colors.orange,
                  ),
                ),
              ],
                mainAxisAlignment: MainAxisAlignment.center,
              ),

            ],
          ),
        )
    );
  }

  // 호출 시 일시적으로 위치 정보를 받아옴
  void getLocation() async {
    bool serviceEnabled;
    LocationPermission permission;
    double lat, lon;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print("위치 정보 서비스 사용 불가");
      return;
    }

    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        print("위치 정보 액세스 거부됨");
        SystemNavigator.pop(); // 앱 종료
        return;
      }
    }
    else {
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      // 정확도 높음으로 위치 정보 받아옴

      print("현재 위치 = " + position.toString());

      lat = double.parse(position.latitude.toString());
      lon = double.parse(position.longitude.toString());
      lm.now = LatLng(lat, lon);

      _mapController.animateCamera(CameraUpdate.newLatLngZoom(lm.now, 14));
      // 현재 위치로 카메라 설정

      _currentMarker = Marker(markerId: const MarkerId("now"),
        position: lm.now,
        icon: _markerIcon,
      );

      setState(() {
        _markers.add(_currentMarker);
      });
    }
  }

  // 실시간 위치 탐색
  void asyncGetLocation() async {
    var locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5
    );

    // 스트림을 통해서 위치 정보가 (distanceFilter)m 변화할 때마다 위치 정보를 다시 받아오도록 함
    StreamSubscription<Position> positionStream = Geolocator.getPositionStream
      (locationSettings: locationSettings).listen((Position? position) async {

      if (position != null) {
        if (_isWalking) { // 산책 중이면

          // 산책 거리 증가
          _length += Geolocator.distanceBetween(_track.last.latitude, _track.last.longitude,
              lm.now.latitude, lm.now.longitude).toInt();

          // 이전 위치들을 이동 경로 배열에 저장
          _track.add(_currentMarker.position);
          // 실시간 위치를 저장해서 지도에 그려줘야

          if (_destinationPoint.markerId != const MarkerId('non')) { // 목적지 마커가 초기 상태가 아니면
            _walkingLength = Geolocator.distanceBetween( // 목적지까지의 거리 계산 => 근데 이거 직선 경로일텐데...?
                lm.now.latitude, lm.now.longitude,
                _destinationPoint.position.latitude,
                _destinationPoint.position.longitude).toInt();
          } else {
            _walkingLength = 0;
          }
        }
        lm.now = LatLng(position.latitude, position.longitude);
        _currentMarker = Marker(
            markerId: const MarkerId("now"),
            position: lm.now,
            icon: _markerIcon);

        setState((){
          _markers.add(_currentMarker);
          _mapController.animateCamera(CameraUpdate.newLatLngZoom(lm.now, 14.0));
        });
      }
    });
  }

  // 목적지 마커를 추가하는 메소드
  void _addDestination(var point) {
    _destinationPoint = Marker(markerId: const MarkerId('destination'),
      position: point,
    );

    var dLength = Geolocator.distanceBetween(lm.now.latitude, lm.now.longitude,
        point.latitude, point.longitude);

    setState((){
      _markers.add(_destinationPoint);
      _walkingLength = dLength.toInt();
    });
  }

  // 목적지를 선택하지 않고 산책 버튼을 눌렀을 때 안내창을 띄우기 위한 메소드
  void _plzChooseDestination(BuildContext context) {
    showDialog(context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            content: const Text("목적지를 선택해주세요!"),
            actions: [
              TextButton(onPressed: (){
                Navigator.of(context).pop();
              },
                  child: const Text("확인"))
            ],
          );
        }
    );
  }

  // 일기 작성을 질의하는 창을 띄우는 메소드
  /// 산책 완료 버튼에 onPressed: _askMakeDiary 형태로 주면 됩니다.
  /// 만약에 팝업 창 띄우는 거 말고도 처리가 필요하다면,
  /// onPressed: () {
  ///   구현하실 내용
  ///   askMakeDiary(context)
  /// } -> 이런식으로 사용하시면 됩니다
  /// 이게 화면 위에 Dairy 클래스를 띄우는거라서 하단 탭바가 안 떠요.. 이건 저도 해결해보고 싶었는데 딱히 방법이 없더라고요
  /// 돌아오는 건 뒤로가기 버튼으로 돌아올 수 있긴 해요.
  void askMakeDiary(BuildContext context) {
    showDialog(context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            content: const Text("일기를 작성하시겠습니까?"),
            actions: [
              TextButton(
                  onPressed: () async {
                    print("일기 작성 버튼 클릭");
                    Navigator.of(context).pop();
                    Navigator.of(context).push(MaterialPageRoute(builder: (context) => Diary()));
                  },
                  child: const Text("확인")),
              TextButton(
                  onPressed: (){
                    print("일기 작성 하지 않기 클릭");
                    Navigator.of(context).pop();
                  },
                  child: const Text("취소")),
            ],
          );
        });
  }

  // 목적지를 입력하면 위경도를 받아오는 메소드
  void _inputDestination(String value) async{

    final url = Uri.parse("https://maps.googleapis.com/maps/api/place/findplacefromtext/json"
        "?fields=geometry" // 반환 받을 내용
        "&input=$value" // 검색어
        "&inputtype=textquery"
        "&locationbias=circle%3A2000${lm.now.latitude}%2C${lm.now.longitude}" // 검색 중심지
        "&language=ko" // 반환값의 언어
        "&key=AIzaSyCxnMmwLCN6PlyGaqXd8Z7BTqCbVQ35bXk");

    final response = await http.get(url);


    double lat = jsonDecode(response.body)['candidates'][0]['geometry']['location']['lat'];
    double lng = jsonDecode(response.body)['candidates'][0]['geometry']['location']['lng'];

    _addDestination(LatLng(lat, lng));

    print('목적지 갱신');
  }

  // 파일 입출력을 위한 메소드들
  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }
  Future<File> get _localFile async {
    final path = await _localPath;
    return File('$path/response.txt');
  }
  Future<File> writeContext(context) async {
    final file = await _localFile;
    return file.writeAsString('$context');
  }
}