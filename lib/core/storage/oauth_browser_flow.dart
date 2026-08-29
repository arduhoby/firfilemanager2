import 'dart:async';
import 'dart:io';

import 'package:oauth2/oauth2.dart' as oauth2;
import 'package:url_launcher/url_launcher.dart';

/// Shared loopback OAuth flow for desktop cloud providers.
///
/// Providers keep their own scopes and endpoints, while callback handling and
/// browser UX remain one canonical implementation.
class OAuthBrowserFlow {
  const OAuthBrowserFlow._();

  static Future<oauth2.Client> authorize({
    required oauth2.AuthorizationCodeGrant grant,
    List<String> scopes = const [],
  }) async {
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: false,
    );
    final redirect = Uri(
      scheme: 'http',
      host: 'localhost',
      port: server.port,
      path: '/oauth/callback',
    );

    try {
      final authUrl = grant.getAuthorizationUrl(redirect, scopes: scopes);
      if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
        throw StateError('Yetkilendirme sayfası açılamadı.');
      }

      final request = await server
          .where((request) => request.uri.path == redirect.path)
          .first
          .timeout(const Duration(minutes: 3));
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..write(
          '<!doctype html><meta charset="utf-8">'
          '<title>Fir File Manager</title>'
          '<p>Bağlantı tamamlandı. Bu pencereyi kapatabilirsiniz.</p>',
        );
      await request.response.close();

      final params = request.uri.queryParameters;
      if (params.containsKey('error')) {
        throw StateError(params['error_description'] ?? params['error']!);
      }
      return await grant.handleAuthorizationResponse(
        Map<String, String>.from(params),
      );
    } finally {
      await server.close(force: true);
    }
  }
}
