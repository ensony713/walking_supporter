import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

class LocationManager {
  late LatLng now; // 현재 위치
  late LatLng destination; // 도착지 위치
  String destinationName = "이름";
  String destinationAddr = "주소"; // 목적지 주소
  String destinationWidth = "0m"; // 현재 위치에서 목적지까지 거리

  List<LatLng> navigationPoint = [];
  Map<PolylineId, Polyline> naviLines = <PolylineId, Polyline> {};

  set setName(String n) {
    destinationName = n;
  }

  set setNow(LatLng p) {
    now = p;
  }

  Future<Map<String, dynamic>> navigation() async {
    Map<String, dynamic> map = {};

    if (destinationName == "이름") {
      print('지점 선택 없이 길찾기가 호출됨');
      return map;
    }

    final url = Uri.parse("https://maps.googleapis.com/maps/api/directions/json"
        "?origin=${now.latitude},${now..longitude}" // 출발점
        "&destination=$destinationName" // 도착점
        "&mode=transit" // 어떤 방식의 길안내인지
        "&language=ko" // 반환값의 언어
        "&key=AIzaSyCxnMmwLCN6PlyGaqXd8Z7BTqCbVQ35bXk");

    final response = await http.get(url);
    print("길 안내 결과 받아옴");
    //writeContext(response.body); // 받아온 결과를 파일로 저장

    map = jsonDecode(response.body);
    return map;
  }
}