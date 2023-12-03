import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart' as location; // Use 'location' as the prefix for the location package
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:mobile_app_2/consts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../CoordinateClass.dart';

class MapPage extends StatefulWidget {
  const MapPage({Key? key}) : super(key: key);

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  location.Location _locationController = location.Location();
  LatLng? _currentPosition;
  TextEditingController _startLocationController = TextEditingController();
  TextEditingController _destinationLocationController = TextEditingController();
  StreamController<Set<Marker>> _markersController = StreamController<Set<Marker>>();

  final Completer<GoogleMapController> _mapController =
  Completer<GoogleMapController>();

  static const LatLng origin = LatLng( 39.115, -77.166);
  static const LatLng destination = LatLng(7.2906, 80.6337);

  Map<PolylineId, Polyline> polylines = {};

  @override
  void initState() {
    super.initState();
    getLocationUpdates();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Google Maps'),
        actions: [
          IconButton(
            icon: Icon(Icons.directions),
            onPressed: () => _showDirectionsDialog(context),
          ),
        ],
      ),
      body: _currentPosition == null
          ? const Center(
        child: Text("Loading..."),
      )
          : StreamBuilder<Set<Marker>>(
        stream: _markersController.stream,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            Set<Marker> markers = snapshot.data!;
            return GoogleMap(
              onMapCreated: (GoogleMapController controller) =>
                  _mapController.complete(controller),
              initialCameraPosition: CameraPosition(
                target: origin,
                zoom: 15,
              ),
              markers: markers,
              polylines: Set<Polyline>.of(polylines.values),
            );
          } else if (snapshot.hasError) {
            return Center(
              child: Text('Error loading markers: ${snapshot.error}'),
            );
          }
          // You can return a loading indicator or an empty GoogleMap here
          return GoogleMap(
            onMapCreated: (GoogleMapController controller) =>
                _mapController.complete(controller),
            initialCameraPosition: CameraPosition(
              target: origin,
              zoom: 15,
            ),
            polylines: Set<Polyline>.of(polylines.values),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _markersController.close();
    super.dispose();
  }

  Future<void> _buildMarkers(List<LatLng> predictions, List<LatLng> hotspots) async {
    List<Marker> markers = [];
    for (LatLng location in hotspots) {
      markers.add(
        Marker(
          markerId: MarkerId(location.toString()),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          position: location,
        ),
      );
    }
    for (LatLng location in predictions) {
      markers.add(
        Marker(
          markerId: MarkerId(location.toString()),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          position: location,
        ),
      );
    }
    _markersController.add(markers.toSet());
  }

  Future<void> getEstimatedTime(List<LatLng> polylineCoordinates) async {
    for (int i = 0; i < polylineCoordinates.length - 1; i++) {
      LatLng start = polylineCoordinates[i];
      LatLng end = polylineCoordinates[i + 1];

      String apiKey = GOOGLE_API_KEY;
      String apiUrl =
          'https://maps.googleapis.com/maps/api/directions/json?origin=${start.latitude},${start.longitude}&destination=${end.latitude},${end.longitude}&mode=driving&key=$apiKey';

      final response = await http.get(Uri.parse(apiUrl));

      if (response.statusCode == 200) {
        // Parse the response JSON to get duration information
        final data = json.decode(response.body);
        List<dynamic> routes = data['routes'];
        if (routes.isNotEmpty) {
          List<dynamic> legs = routes[0]['legs'];
          if (legs.isNotEmpty) {
            String durationText = legs[0]['duration']['text'];
            print('Estimated time from point $i to ${i + 1}: $durationText');
            // You can store the duration information as needed
          }
        }
      } else {
        print('Error getting directions: ${response.reasonPhrase}');
      }
    }
  }

  Future<void> _showDirectionsDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Enter Directions'),
          content: Scrollbar(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  TextField(
                    controller: _startLocationController,
                    decoration: InputDecoration(labelText: 'Start Location'),
                  ),
                  TextField(
                    controller: _destinationLocationController,
                    decoration:
                    InputDecoration(labelText: 'Destination Location'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                await _getDirections();
                Navigator.of(context).pop();
              },
              child: Text('Get Directions'),
            ),
          ],
        );
      },
    );
  }

  Future<Map<String, List<LatLng>>> sendCoordinatesToServer(List<LatLng> coordinates) async {
    DateTime now = DateTime.now();
    String formattedDateTime = '${now.month}/${now.day}/${now.year} ${now.hour}:${now.minute}';

    // Format coordinates as a list of lists [latitude, longitude]
    List<List<double>> formattedCoordinates = coordinates
        .map((LatLng point) => [point.latitude, point.longitude])
        .toList();

    // Create the request body as JSON
    Map<String, dynamic> requestBody = {
      'Date_Time': formattedDateTime,
      'Coordinates': formattedCoordinates
    };

    String requestBodyJson = jsonEncode(requestBody);

    // Replace the URL with the actual URL of your Flask server
    String apiUrl = 'http://192.168.42.116:5000/predict';

    try {
      // Send POST request
      http.Response response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: requestBodyJson,
      );

      // Parse the response
      if (response.statusCode == 200) {
        // If the request is successful (HTTP 200 OK), parse the response as a list of integers
        Map<String, dynamic> jsonResponse = jsonDecode(response.body);

        if (jsonResponse.containsKey('accident_hotspots') && jsonResponse.containsKey('accident_predictions')) {
          List<dynamic> hotspotsResult = jsonResponse['accident_hotspots'];
          List<dynamic> predictionsResult = jsonResponse['accident_predictions'];

          // Convert the result to a list of lists of LatLng
          List<List<LatLng>> hotspotsList = hotspotsResult
              .map((coordinate) => [
            LatLng(coordinate[0], coordinate[1]),
          ])
              .toList();

          List<List<LatLng>> predictionsList = predictionsResult
              .map((coordinate) => [
            LatLng(coordinate[0], coordinate[1]),
          ])
              .toList();
          List<LatLng> latLngHotspotsResult = hotspotsResult.map((coord) => LatLng(coord[0], coord[1])).toList();
          List<LatLng> latLngPredictionsResult = predictionsResult.map((coord) => LatLng(coord[0], coord[1])).toList();
          return {
            'hotspots': latLngHotspotsResult,
            'predictions': latLngPredictionsResult,
          };
        }
        else {
          return {
            'hotspots': [],
            'predictions': [],
          };
        }
      }
      else {
        return {
          'hotspots': [],
          'predictions': [],
        };
      }
    } catch (e) {
      return {
        'hotspots': [],
        'predictions': [],
      };
    }
  }
  Future<void> _getDirections() async {

    String startLocation = _startLocationController.text;
    String destinationLocation = _destinationLocationController.text;

    List<geocoding.Location> startResults =
    await geocoding.locationFromAddress(startLocation);
    List<geocoding.Location> destinationResults =
    await geocoding.locationFromAddress(destinationLocation);

    if (startResults.isNotEmpty && destinationResults.isNotEmpty) {
      LatLng startLatLng = LatLng(
        startResults.first.latitude!,
        startResults.first.longitude!,
      );
      LatLng destinationLatLng = LatLng(
        destinationResults.first.latitude!,
        destinationResults.first.longitude!,
      );

      List<LatLng> coordinates =
      await getPolylinePoints(startLatLng, destinationLatLng);

      if (coordinates.isNotEmpty) {
        Map<String, List<LatLng>> result = await sendCoordinatesToServer(coordinates);

        List<LatLng> predictions = result['predictions'] ?? [];
        List<LatLng> hotspots = result['hotspots'] ?? [];

        print(predictions.length);
        print(hotspots.length);

        if ((predictions != null && predictions.isNotEmpty)&& (hotspots != null && hotspots.isNotEmpty)) {
          _buildMarkers(predictions, hotspots);
          print("hi");
        }
        else if(hotspots == null && hotspots.isEmpty) {
          _buildMarkers(predictions, []);
        }
        else if(predictions == null && predictions.isEmpty) {
          _buildMarkers([], hotspots);
        }

        generatePolylineFromPoints(coordinates);
        _cameraToPosition(startLatLng);
      } else {
        print('Error: No polyline coordinates available');
      }
    } else {
      print('Error: Unable to retrieve location coordinates');
    }
  }

  Future<List<LatLng>> getPolylinePoints(LatLng startLocation, LatLng destinationLocation) async{
    try {
      List<LatLng> polylineCoordinates = [];
      PolylinePoints polylinePoints = PolylinePoints();
      PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
          'AIzaSyCA5oO5WKylMeHRyDhrK0fNlxdCHkNARCk',
          PointLatLng(startLocation.latitude, startLocation.longitude),
          PointLatLng(destinationLocation.latitude, destinationLocation.longitude),
          travelMode: TravelMode.driving
      );

      if(result.points.isNotEmpty)
      {
        result.points.forEach((PointLatLng point) {
          polylineCoordinates.add(LatLng(point.latitude, point.longitude));
        });
      }
      else{
        print("result points is empty in getting polyline points");
      }
      return polylineCoordinates;
    }
    catch (e) {
      print('Error in getPolylinePoints:');
      return [];
    }
  }

  void generatePolylineFromPoints(List<LatLng> polylineCoordinates) async{
    // await getEstimatedTime(polylineCoordinates);
    // print(polylineCoordinates.length);
    // for (LatLng point in polylineCoordinates) {
    //   print('Latitude: ${point.latitude}, Longitude: ${point.longitude}');
    // }
    PolylineId id = PolylineId("poly");
    Polyline polyline = Polyline(
      polylineId: id,
      color: Colors.blue,
      width: 8,
      points: polylineCoordinates,
    );
    setState(() {
      polylines[id] = polyline;
    });
  }

  Future<void> getLocationUpdates() async {
    bool _serviceEnabled;
    location.PermissionStatus _permissionGranted;

    _serviceEnabled = await _locationController.serviceEnabled();
    if (_serviceEnabled) {
      _serviceEnabled = await _locationController.requestService();
    } else {
      return;
    }

    _permissionGranted = await _locationController.hasPermission();
    if (_permissionGranted == location.PermissionStatus.denied) {
      _permissionGranted = await _locationController.requestPermission();
      if (_permissionGranted != location.PermissionStatus.granted) {
        return;
      }
    }
    _locationController.onLocationChanged
        .listen((location.LocationData currentLocation) {
      if (currentLocation.latitude != null &&
          currentLocation.longitude != null) {
        setState(() {
          _currentPosition =
              LatLng(currentLocation.latitude!, currentLocation.longitude!);
        });
      }
    });
  }

  Future<void> _cameraToPosition (LatLng pos) async {
    final GoogleMapController controller = await _mapController.future;
    CameraPosition _newCameraPosition = CameraPosition(target: pos, zoom: 15  );
    await controller.animateCamera(
        CameraUpdate.newCameraPosition(_newCameraPosition));
  }
}

