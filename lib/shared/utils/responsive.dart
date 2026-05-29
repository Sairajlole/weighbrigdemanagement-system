import 'package:flutter/material.dart';

class Responsive {
  static double _scale = 1.0;
  static Size _screenSize = const Size(1920, 1080);

  static void init(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    _screenSize = size;
    _scale = (size.width / 1920).clamp(0.5, 1.3);
  }

  static double get scale => _scale;
  static Size get screenSize => _screenSize;

  static double sp(double size) => size * _scale;
  static double wp(double percent) => _screenSize.width * percent / 100;
  static double hp(double percent) => _screenSize.height * percent / 100;
}

extension ResponsiveNum on num {
  double get rs => toDouble() * Responsive.scale;
}
