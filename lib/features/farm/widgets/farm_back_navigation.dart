import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class FarmBackNavigationScope extends StatelessWidget {
  const FarmBackNavigationScope({
    super.key,
    required this.fallbackPath,
    required this.child,
  });

  final String fallbackPath;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go(fallbackPath);
      },
      child: child,
    );
  }
}

class FarmBackButton extends StatelessWidget {
  const FarmBackButton({super.key, required this.fallbackPath});

  final String fallbackPath;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const Key('farm-safe-back-button'),
    tooltip: 'Back',
    onPressed: () {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(fallbackPath);
      }
    },
    icon: const Icon(Icons.arrow_back_rounded),
  );
}
