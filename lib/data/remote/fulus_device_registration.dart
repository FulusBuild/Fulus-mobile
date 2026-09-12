import 'package:dio/dio.dart';

import 'api_client.dart';

class FulusDeviceRegistration {
  FulusDeviceRegistration({
    required ApiClient client,
    required String functionBaseUrl,
  })  : _client = client,
        _functionBaseUrl = functionBaseUrl;

  final ApiClient _client;
  final String _functionBaseUrl;

  Future<FulusRegisteredDevice> register({
    required String businessId,
    required String deviceClientId,
    String? deviceName,
    String? platform,
    String? appVersion,
  }) async {
    try {
      final response = await Dio(BaseOptions(baseUrl: _functionBaseUrl)).post(
        '',
        data: {
          'action': 'register_device',
          'business_id': businessId,
          'device_client_id': deviceClientId,
          if (deviceName != null) 'device_name': deviceName,
          if (platform != null) 'platform': platform,
          if (appVersion != null) 'app_version': appVersion,
        },
        options: Options(headers: {
          'content-type': 'application/json',
          if (_client.serverAccessToken != null)
            'Authorization': 'Bearer ${_client.serverAccessToken}',
        }),
      );
      final root = Map<String, dynamic>.from(response.data as Map);
      final data = Map<String, dynamic>.from(root['data'] as Map);
      return FulusRegisteredDevice.fromJson(
        Map<String, dynamic>.from(data['device'] as Map),
      );
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }
}

class FulusRegisteredDevice {
  const FulusRegisteredDevice({
    required this.id,
    required this.businessId,
    required this.deviceClientId,
    required this.status,
  });

  final String id;
  final String businessId;
  final String deviceClientId;
  final String status;

  factory FulusRegisteredDevice.fromJson(Map<String, dynamic> json) =>
      FulusRegisteredDevice(
        id: json['id'] as String,
        businessId: json['business_id'] as String,
        deviceClientId: json['device_client_id'] as String,
        status: json['status'] as String,
      );
}
