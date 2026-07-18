import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

class AveraLogo extends StatelessWidget {
  const AveraLogo({
    super.key,
    this.size = 72,
    this.showWordmark = false,
    this.wordmarkColor,
  });

  final double size;
  final bool showWordmark;
  final Color? wordmarkColor;

  @override
  Widget build(BuildContext context) {
    final mark = SizedBox.square(
      dimension: size,
      child: SvgPicture.asset(
        'assets/branding/avera_logo.svg',
        fit: BoxFit.contain,
        semanticsLabel: 'AVERA logo',
      ),
    );

    if (!showWordmark) return mark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        SizedBox(height: size * .12),
        Text(
          'AVERA',
          style: GoogleFonts.sora(
            color: wordmarkColor ?? Theme.of(context).colorScheme.onSurface,
            fontSize: size * .2,
            fontWeight: FontWeight.w800,
            letterSpacing: 4,
          ),
        ),
      ],
    );
  }
}
