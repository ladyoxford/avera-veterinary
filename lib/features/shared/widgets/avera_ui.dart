import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

AveraTextStyles averaText(BuildContext context) =>
    Theme.of(context).extension<AveraTextStyles>()!;

class AveraPageHeader extends StatelessWidget {
  const AveraPageHeader({super.key, required this.title, this.subtitle});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: averaText(context).pageTitle),
      if (subtitle?.trim().isNotEmpty == true) ...[
        const SizedBox(height: AveraSpacing.titleToSubtitleGap),
        Text(subtitle!, style: averaText(context).pageSubtitle),
      ],
    ],
  );
}

class AveraSectionHeader extends StatelessWidget {
  const AveraSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
  });
  final String title;
  final String? subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: averaText(context).sectionTitle),
            if (subtitle?.trim().isNotEmpty == true) ...[
              const SizedBox(height: AveraSpacing.titleToSubtitleGap),
              Text(subtitle!, style: averaText(context).sectionSubtitle),
            ],
          ],
        ),
      ),
      if (action != null) action!,
    ],
  );
}

class AveraSurfaceCard extends StatelessWidget {
  const AveraSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AveraSpacing.cardPadding),
    this.color,
    this.outlined = false,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final bool outlined;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: Card(
        color: color,
        clipBehavior: Clip.antiAlias,
        shape: outlined
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AveraSpacing.cardRadius),
                side: BorderSide(color: scheme.outlineVariant),
              )
            : null,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// A full-width navigation card for settings and administrative destinations.
/// It deliberately keeps the text column flexible so long clinic labels do not
/// force the trailing affordance outside a narrow screen.
class AveraAdministrationCard extends StatelessWidget {
  const AveraAdministrationCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AveraSurfaceCard(
      padding: EdgeInsets.zero,
      child: Semantics(
        button: onTap != null,
        label: '$title. $subtitle',
        child: InkWell(
          borderRadius: BorderRadius.circular(AveraSpacing.cardRadius),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AveraSpacing.cardPadding),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(width: AveraSpacing.compactRowGap),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: averaText(context).listItemTitle),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: averaText(context).listItemSubtitle,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AveraSpacing.compactRowGap),
                Icon(
                  Icons.chevron_right_rounded,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AveraLabeledFieldCard extends StatelessWidget {
  const AveraLabeledFieldCard({
    super.key,
    required this.label,
    required this.child,
    this.surfaceColor,
    this.outlined = true,
  });
  final String label;
  final Widget child;
  final Color? surfaceColor;
  final bool outlined;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label.toUpperCase(), style: averaText(context).sectionLabel),
      const SizedBox(height: 8),
      AveraSurfaceCard(
        color:
            surfaceColor ?? Theme.of(context).colorScheme.surfaceContainerHigh,
        outlined: outlined,
        child: child,
      ),
    ],
  );
}

class AveraLabeledTextField extends StatelessWidget {
  const AveraLabeledTextField({
    super.key,
    required this.label,
    required this.controller,
    required this.hintText,
    this.enabled = true,
    this.readOnly = false,
    this.minLines = 1,
    this.maxLines = 1,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.onChanged,
    this.onTap,
    this.suffixIcon,
  });

  final String label;
  final TextEditingController controller;
  final String hintText;
  final bool enabled;
  final bool readOnly;
  final int minLines;
  final int maxLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final Widget? suffixIcon;

  @override
  Widget build(BuildContext context) => AveraLabeledFieldCard(
    label: label,
    child: TextFormField(
      controller: controller,
      enabled: enabled,
      readOnly: readOnly,
      minLines: minLines,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      validator: validator,
      onChanged: onChanged,
      onTap: onTap,
      style: averaText(context).fieldValue,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: averaText(context).fieldPlaceholder,
        filled: false,
        isCollapsed: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        contentPadding: EdgeInsets.zero,
        suffixIcon: suffixIcon,
        suffixIconConstraints: const BoxConstraints(
          minWidth: AveraSpacing.minimumTapTarget,
          minHeight: AveraSpacing.minimumTapTarget,
        ),
      ),
    ),
  );
}

class AveraLabeledDropdownField<T> extends StatelessWidget {
  const AveraLabeledDropdownField({
    super.key,
    required this.label,
    required this.hintText,
    required this.items,
    required this.onChanged,
    this.value,
    this.validator,
    this.helperText,
    this.autovalidateMode,
  });

  final String label;
  final String hintText;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? Function(T?)? validator;
  final String? helperText;
  final AutovalidateMode? autovalidateMode;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AveraLabeledFieldCard(
        label: label,
        child: DropdownButtonFormField<T>(
          value: value,
          isExpanded: true,
          items: items,
          onChanged: onChanged,
          validator: validator,
          autovalidateMode: autovalidateMode,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          style: averaText(context).fieldValue,
          hint: Text(
            hintText,
            style: averaText(context).fieldPlaceholder,
            overflow: TextOverflow.ellipsis,
          ),
          decoration: const InputDecoration(
            filled: false,
            isCollapsed: true,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
      if (helperText?.trim().isNotEmpty == true) ...[
        const SizedBox(height: 6),
        Text(helperText!, style: averaText(context).caption),
      ],
    ],
  );
}

class AveraLabeledSwitchField extends StatelessWidget {
  const AveraLabeledSwitchField({
    super.key,
    required this.label,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String label;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => AveraLabeledFieldCard(
    label: label,
    child: SwitchListTile(
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: averaText(context).fieldValue),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: averaText(context).caption),
    ),
  );
}

class AveraPrimaryActionButton extends StatelessWidget {
  const AveraPrimaryActionButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.loading = false,
  });
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton.icon(
      onPressed: loading ? null : onPressed,
      icon: loading
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon ?? Icons.check_rounded),
      label: Text(label, style: averaText(context).buttonLabel),
    ),
  );
}
