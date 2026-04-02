import 'package:flutter/material.dart';

/// См. `assets/branding/aist_logo.png` (оригинал 1453×1390, прозрачный фон).
const String kAistLogoAsset = 'assets/branding/aist_logo.png';

/// Соотношение сторон логотипа (ширина / высота) для корректного масштаба в шапке.
const double kAistLogoAspect = 1453 / 1390;

const String kAppTitle = 'АИСТ';

/// Заголовок с логотипом для AppBar.
class AistAppBarTitle extends StatelessWidget {
  const AistAppBarTitle({super.key, this.logoHeight = 36});

  final double logoHeight;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleLarge;
    final logoW = logoHeight * kAistLogoAspect;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: logoHeight,
          width: logoW,
          child: Image.asset(
            kAistLogoAsset,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
            filterQuality: FilterQuality.high,
            isAntiAlias: true,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) {
              return Icon(
                Icons.broken_image_outlined,
                size: logoHeight * 0.85,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              );
            },
          ),
        ),
        const SizedBox(width: 10),
        Text(kAppTitle, style: style),
      ],
    );
  }
}
