class AppConfig {
  /// Toggle this to `true` when deploying to production (the cloud)
  static const bool isProduction = false;

  /// Replace this with your Render.com backend URL
  static const String productionBackendUrl = 'https://your-unibuy-backend-xyz.onrender.com';

  /// Local development URLs
  static const String localWebBackendUrl = 'http://localhost:5000';
  static const String localAndroidBackendUrl = 'http://10.0.2.2:5000';

  /// Automatically gets the correct base URL for your APIs
  static String get baseUrl {
    if (isProduction) {
      return productionBackendUrl;
    }
    // ignore: undefined_prefixed_name
    const isWeb = bool.fromEnvironment('dart.library.js_util');
    return isWeb ? localWebBackendUrl : localAndroidBackendUrl;
  }
}
