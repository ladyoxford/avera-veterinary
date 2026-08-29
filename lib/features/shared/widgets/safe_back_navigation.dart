import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SafeBackNavigationScope extends StatelessWidget {
  const SafeBackNavigationScope({
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

class SafeBackButton extends StatelessWidget {
  const SafeBackButton({super.key, required this.fallbackPath, this.buttonKey});

  final String fallbackPath;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) => IconButton(
    key: buttonKey,
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
