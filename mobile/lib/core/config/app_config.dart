import 'package:flutter/foundation.dart';

class AppConfig {
  AppConfig({required String apiBaseUrl})
    : apiBaseUrl = '${apiBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/' {
    final uri = Uri.tryParse(this.apiBaseUrl);
    if (uri == null ||
        !uri.hasAuthority ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ArgumentError('API_BASE_URL must be an HTTP(S) API URL.');
    }
  }

  factory AppConfig.fromEnvironment() {
    const configured = String.fromEnvironment('API_BASE_URL');
    return AppConfig(
      apiBaseUrl: configured.isNotEmpty
          ? configured
          : (!kIsWeb && defaultTargetPlatform == TargetPlatform.android
                ? 'http://10.0.2.2:3000/api'
                : 'http://localhost:3000/api'),
    );
  }

  final String apiBaseUrl;
}
