import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

enum SocialProvider { google, apple }

class SocialIdentityCredential {
  const SocialIdentityCredential({
    required this.provider,
    required this.idToken,
    this.nonce,
  });

  final SocialProvider provider;
  final String idToken;
  final String? nonce;
}

abstract interface class SocialIdentityClient {
  Future<SocialIdentityCredential?> authenticate(SocialProvider provider);
}

class NativeSocialIdentityClient implements SocialIdentityClient {
  NativeSocialIdentityClient();

  static const _googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );
  static const _appleServiceId = String.fromEnvironment('APPLE_SERVICE_ID');
  static const _appleRedirectUri = String.fromEnvironment('APPLE_REDIRECT_URI');

  @override
  Future<SocialIdentityCredential?> authenticate(SocialProvider provider) =>
      switch (provider) {
        SocialProvider.google => _google(),
        SocialProvider.apple => _apple(),
      };

  Future<SocialIdentityCredential?> _google() async {
    if (_googleServerClientId.isEmpty) {
      throw const SocialIdentityConfigurationException(
        'Google sign-in requires GOOGLE_SERVER_CLIENT_ID.',
      );
    }
    final account = await GoogleSignIn(
      scopes: const ['email'],
      serverClientId: _googleServerClientId,
    ).signIn();
    if (account == null) return null;
    final authentication = await account.authentication;
    final idToken = authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw const SocialIdentityConfigurationException(
        'Google did not return an identity token for the configured backend client.',
      );
    }
    return SocialIdentityCredential(
      provider: SocialProvider.google,
      idToken: idToken,
    );
  }

  Future<SocialIdentityCredential?> _apple() async {
    final rawNonce = _secureNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
    WebAuthenticationOptions? webOptions;
    if (!Platform.isIOS && !Platform.isMacOS) {
      if (_appleServiceId.isEmpty || _appleRedirectUri.isEmpty) {
        throw const SocialIdentityConfigurationException(
          'Apple sign-in requires APPLE_SERVICE_ID and APPLE_REDIRECT_URI on this platform.',
        );
      }
      webOptions = WebAuthenticationOptions(
        clientId: _appleServiceId,
        redirectUri: Uri.parse(_appleRedirectUri),
      );
    }
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [AppleIDAuthorizationScopes.email],
        nonce: hashedNonce,
        webAuthenticationOptions: webOptions,
      );
      final idToken = credential.identityToken;
      if (idToken == null || idToken.isEmpty) {
        throw const SocialIdentityConfigurationException(
          'Apple did not return an identity token.',
        );
      }
      return SocialIdentityCredential(
        provider: SocialProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) return null;
      rethrow;
    }
  }

  String _secureNonce([int length = 32]) {
    const alphabet =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }
}

class SocialIdentityConfigurationException implements Exception {
  const SocialIdentityConfigurationException(this.message);

  final String message;

  @override
  String toString() => message;
}
