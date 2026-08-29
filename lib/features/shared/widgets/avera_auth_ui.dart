import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'avera_logo.dart';

class AveraAuthScaffold extends StatelessWidget {
  const AveraAuthScaffold({
    super.key,
    required this.child,
    this.showBrand = true,
    this.backTitle,
    this.onBack,
    this.footer,
    this.maxWidth = 620,
  });

  final Widget child;
  final bool showBrand;
  final String? backTitle;
  final VoidCallback? onBack;
  final Widget? footer;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final darkTheme = AppTheme.dark();
    return Theme(
      data: darkTheme,
      child: Builder(
        builder: (context) => Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  constraints.maxWidth < 420 ? 22 : 32,
                  26,
                  constraints.maxWidth < 420 ? 22 : 32,
                  28 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: maxWidth,
                      minHeight: (constraints.maxHeight - 54)
                          .clamp(0.0, double.infinity)
                          .toDouble(),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (backTitle != null)
                          AveraBackHeader(title: backTitle!, onBack: onBack)
                        else if (showBrand)
                          const AveraBrandLockup(),
                        if (showBrand || backTitle != null)
                          const SizedBox(height: 34),
                        child,
                        if (footer != null) ...[
                          const SizedBox(height: 34),
                          Center(child: footer!),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AveraBrandLockup extends StatelessWidget {
  const AveraBrandLockup({super.key});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const AveraLogo(size: 52),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AVERA',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              'VETERINARY PRACTICE PLATFORM',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class AveraBackHeader extends StatelessWidget {
  const AveraBackHeader({super.key, required this.title, this.onBack});

  final String title;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton(
        tooltip: 'Back',
        onPressed: onBack ?? () => Navigator.maybePop(context),
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontSize: 26,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    ],
  );
}

class AveraAuthCard extends StatelessWidget {
  const AveraAuthCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.outlineVariant),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class AveraFormLabel extends StatelessWidget {
  const AveraFormLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label.toUpperCase(),
    style: Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w800,
      letterSpacing: .6,
    ),
  );
}

class AveraAuthField extends StatelessWidget {
  const AveraAuthField({
    super.key,
    required this.label,
    required this.controller,
    required this.hintText,
    this.icon,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.helperText,
    this.obscureText = false,
    this.suffixIcon,
    this.onFieldSubmitted,
    this.autofillHints,
  });

  final String label;
  final TextEditingController controller;
  final String hintText;
  final IconData? icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final String? helperText;
  final bool obscureText;
  final Widget? suffixIcon;
  final ValueChanged<String>? onFieldSubmitted;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AveraFormLabel(label),
        const SizedBox(height: 9),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          validator: validator,
          obscureText: obscureText,
          onFieldSubmitted: onFieldSubmitted,
          autofillHints: autofillHints,
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: icon == null ? null : Icon(icon),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: colors.surfaceContainerHigh,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 18,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: colors.outlineVariant),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: colors.primary, width: 1.6),
            ),
          ),
        ),
        if (helperText != null) ...[
          const SizedBox(height: 7),
          Text(helperText!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }
}
