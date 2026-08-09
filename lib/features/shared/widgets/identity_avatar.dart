import 'package:flutter/material.dart';

import 'identity_avatar_image.dart';

const _avatarColors = [
  Color(0xFF397D83),
  Color(0xFF4A6FA5),
  Color(0xFF7B6699),
  Color(0xFF7D7050),
  Color(0xFF4B7D62),
];

String averaInitials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty);
  return parts.take(2).map((part) => part[0]).join().toUpperCase();
}

class AveraIdentityAvatar extends StatelessWidget {
  const AveraIdentityAvatar({
    super.key,
    required this.name,
    this.photoReference,
    this.size = 46,
    this.onTap,
  });

  final String name;
  final String? photoReference;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final reference = photoReference?.trim();
    final image = reference == null || reference.isEmpty
        ? null
        : reference.startsWith('http')
        ? NetworkImage(reference) as ImageProvider<Object>
        : localIdentityImage(reference);
    final color = _avatarColors[name.hashCode.abs() % _avatarColors.length];
    final fallback = ColoredBox(
      color: color,
      child: Center(
        child: Text(
          averaInitials(name),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Colors.white,
            fontSize: size * .32,
          ),
        ),
      ),
    );
    final avatar = Semantics(
      image: onTap == null,
      button: onTap != null,
      label: onTap == null ? '$name profile photo' : 'Change profile photo',
      child: Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: .6),
          ),
        ),
        child: ClipOval(
          child: image == null
              ? fallback
              : Image(
                  image: image,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => fallback,
                ),
        ),
      ),
    );
    return onTap == null
        ? avatar
        : InkWell(
            borderRadius: BorderRadius.circular(size / 2),
            onTap: onTap,
            child: avatar,
          );
  }
}
