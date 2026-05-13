import 'dart:convert';

import 'package:http/http.dart' as http;

class KakaoLocalSearchResult {
  const KakaoLocalSearchResult({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final String address;
  final double latitude;
  final double longitude;
}

class KakaoLocalService {
  KakaoLocalService({
    String? restApiKey,
    http.Client? client,
  })  : _restApiKey = restApiKey ??
            const String.fromEnvironment(
              'KAKAO_REST_API_KEY',
              defaultValue: 'b947bc19e0d5b5e1022d1b5573f07ae4',
            ),
        _client = client ?? http.Client();

  final String _restApiKey;
  final http.Client _client;

  bool get hasKey => _restApiKey.trim().isNotEmpty;

  Future<List<KakaoLocalSearchResult>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const <KakaoLocalSearchResult>[];
    if (!hasKey) {
      throw const KakaoLocalException(
        'KAKAO_REST_API_KEY 실행 옵션이 필요합니다.',
      );
    }

    final results = <KakaoLocalSearchResult>[];
    results.addAll(await _searchKeyword(trimmed));
    results.addAll(await _searchAddress(trimmed));
    return _dedupe(results).take(8).toList(growable: false);
  }

  Future<KakaoLocalSearchResult?> reverseGeocode({
    required double latitude,
    required double longitude,
  }) async {
    if (!hasKey) return null;
    final body = await _getJson(
      Uri.https('dapi.kakao.com', '/v2/local/geo/coord2address.json', {
        'x': longitude.toString(),
        'y': latitude.toString(),
      }),
    );
    final documents = body['documents'];
    if (documents is! List || documents.isEmpty) return null;
    return _coordDocumentToResult(
      documents.first,
      latitude: latitude,
      longitude: longitude,
    );
  }

  Future<List<KakaoLocalSearchResult>> _searchKeyword(String query) async {
    final body = await _getJson(
      Uri.https('dapi.kakao.com', '/v2/local/search/keyword.json', {
        'query': query,
        'size': '7',
      }),
    );
    final documents = body['documents'];
    if (documents is! List) return const <KakaoLocalSearchResult>[];
    return documents
        .map(_keywordDocumentToResult)
        .whereType<KakaoLocalSearchResult>()
        .toList(growable: false);
  }

  Future<List<KakaoLocalSearchResult>> _searchAddress(String query) async {
    final body = await _getJson(
      Uri.https('dapi.kakao.com', '/v2/local/search/address.json', {
        'query': query,
        'size': '5',
      }),
    );
    final documents = body['documents'];
    if (documents is! List) return const <KakaoLocalSearchResult>[];
    return documents
        .map(_addressDocumentToResult)
        .whereType<KakaoLocalSearchResult>()
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: {'Authorization': 'KakaoAK $_restApiKey'},
      ).timeout(const Duration(seconds: 8));
    } catch (error) {
      throw KakaoLocalException(
        '카카오 위치 검색 연결 실패: $error',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = response.body.trim();
      throw KakaoLocalException(
        body.isEmpty
            ? '카카오 위치 검색 실패 (${response.statusCode})'
            : '카카오 위치 검색 실패 (${response.statusCode}) $body',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
    return const <String, dynamic>{};
  }

  KakaoLocalSearchResult? _keywordDocumentToResult(Object? document) {
    if (document is! Map<String, dynamic>) return null;
    final name = _readString(document['place_name']);
    final address = _readString(document['road_address_name']).isNotEmpty
        ? _readString(document['road_address_name'])
        : _readString(document['address_name']);
    final longitude = double.tryParse(_readString(document['x']));
    final latitude = double.tryParse(_readString(document['y']));
    if (name.isEmpty ||
        address.isEmpty ||
        latitude == null ||
        longitude == null) {
      return null;
    }
    return KakaoLocalSearchResult(
      name: name,
      address: address,
      latitude: latitude,
      longitude: longitude,
    );
  }

  KakaoLocalSearchResult? _addressDocumentToResult(Object? document) {
    if (document is! Map<String, dynamic>) return null;
    final roadAddress = document['road_address'];
    final addressMap = document['address'];
    final roadAddressName = roadAddress is Map<String, dynamic>
        ? _readString(roadAddress['address_name'])
        : '';
    final buildingName = roadAddress is Map<String, dynamic>
        ? _readString(roadAddress['building_name'])
        : '';
    final landAddressName = addressMap is Map<String, dynamic>
        ? _readString(addressMap['address_name'])
        : _readString(document['address_name']);
    final address =
        roadAddressName.isNotEmpty ? roadAddressName : landAddressName;
    final name = buildingName.isNotEmpty ? buildingName : address;
    final longitude = double.tryParse(_readString(document['x']));
    final latitude = double.tryParse(_readString(document['y']));
    if (address.isEmpty || latitude == null || longitude == null) return null;
    return KakaoLocalSearchResult(
      name: name,
      address: address,
      latitude: latitude,
      longitude: longitude,
    );
  }

  KakaoLocalSearchResult? _coordDocumentToResult(
    Object? document, {
    required double latitude,
    required double longitude,
  }) {
    if (document is! Map<String, dynamic>) return null;
    final roadAddress = document['road_address'];
    final addressMap = document['address'];
    final roadAddressName = roadAddress is Map<String, dynamic>
        ? _readString(roadAddress['address_name'])
        : '';
    final buildingName = roadAddress is Map<String, dynamic>
        ? _readString(roadAddress['building_name'])
        : '';
    final landAddressName = addressMap is Map<String, dynamic>
        ? _readString(addressMap['address_name'])
        : '';
    final address =
        roadAddressName.isNotEmpty ? roadAddressName : landAddressName;
    if (address.isEmpty) return null;
    return KakaoLocalSearchResult(
      name: buildingName.isNotEmpty ? buildingName : address,
      address: address,
      latitude: latitude,
      longitude: longitude,
    );
  }

  List<KakaoLocalSearchResult> _dedupe(List<KakaoLocalSearchResult> values) {
    final seen = <String>{};
    final deduped = <KakaoLocalSearchResult>[];
    for (final value in values) {
      final key = '${value.name}|${value.address}';
      if (seen.add(key)) deduped.add(value);
    }
    return deduped;
  }

  String _readString(Object? value) => value?.toString().trim() ?? '';

  void close() => _client.close();
}

class KakaoLocalException implements Exception {
  const KakaoLocalException(this.message);

  final String message;

  @override
  String toString() => message;
}
