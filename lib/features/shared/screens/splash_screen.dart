import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/remote/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../widgets/avera_logo.dart';

/// Continues the native Android splash with a brief branded Flutter handoff.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _animationDuration = Duration(milliseconds: 1150);
  static const _wordmarkHoldDuration = Duration(seconds: 2);
  static final _minimumDisplayDuration =
      _animationDuration + _wordmarkHoldDuration;

  late final AnimationController _controller;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoScale;
  late final Completer<void> _minimumDelay;
  Timer? _routeTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _animationDuration)
      ..forward();
    _logoOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, .45, curve: Curves.easeOut),
    );
    _logoScale = Tween<double>(begin: .86, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, .55, curve: Curves.easeOutCubic),
      ),
    );
    _minimumDelay = Completer<void>();
    _routeTimer = Timer(_minimumDisplayDuration, _minimumDelay.complete);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_routeAfterAnimation());
    });
  }

  @override
  void dispose() {
    _routeTimer?.cancel();
    if (!_minimumDelay.isCompleted) _minimumDelay.complete();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _routeAfterAnimation() async {
    final destination = _resolveDestination();
    await _minimumDelay.future;
    final route = await destination;
    if (!mounted) return;
    context.go(route);
  }

  Future<String> _resolveDestination() async {
    if (BackendConfiguration.isLocalMode) return '/login';

    // The probe is intentionally not awaited. Session restoration and offline
    // authorization decide routing while connectivity continues independently.
    unawaited(ref.read(cloudConnectivityProvider.future));
    try {
      final session = await ref.read(userSessionProvider.future);
      return session.isPlatformOwner ? '/platform' : '/dashboard';
    } catch (_) {
      final offline = await ref
          .read(offlineAuthorizationServiceProvider)
          .validSnapshot();
      if (offline != null &&
          await ref.read(offlineAuthorizationServiceProvider).hasPin) {
        return '/offline-unlock';
      }
      return '/login';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primary,
      body: SafeArea(
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FadeTransition(
                  opacity: _logoOpacity,
                  child: ScaleTransition(
                    scale: _logoScale,
                    child: const AveraLogo(
                      size: 164,
                      variant: AveraLogoVariant.splash,
                    ),
                  ),
                ),
                const SizedBox(
                  key: ValueKey('splash-logo-wordmark-gap'),
                  height: 20,
                ),
                Semantics(
                  label: 'AVERA',
                  child: ExcludeSemantics(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(5, _buildWordmarkLetter),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWordmarkLetter(int index) {
    const wordmark = 'AVERA';
    final start = .34 + (index * .12);
    final visible = ((_controller.value - start) / .16)
        .clamp(0.0, 1.0)
        .toDouble();
    return Opacity(
      opacity: visible,
      child: Transform.translate(
        offset: Offset(0, (1 - visible) * 10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Text(
            wordmark[index],
            style: const TextStyle(
              fontFamily: 'Sora',
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}
