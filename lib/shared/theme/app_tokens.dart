import 'package:flutter/material.dart';
import 'package:weighbridgemanagement/shared/utils/responsive.dart';

class AppSpacing {
  AppSpacing._();

  static double get xxs => 2.rs;
  static double get xs => 4.rs;
  static double get sm => 8.rs;
  static double get md => 12.rs;
  static double get lg => 16.rs;
  static double get xl => 24.rs;
  static double get xxl => 32.rs;
  static double get xxxl => 48.rs;

  static EdgeInsets get pagePadding => EdgeInsets.all(xl);
  static EdgeInsets get cardPadding => EdgeInsets.all(lg);
  static EdgeInsets get sectionPadding => EdgeInsets.symmetric(horizontal: xl, vertical: lg);
  static EdgeInsets get inputPadding => EdgeInsets.symmetric(horizontal: md, vertical: sm);
}

class AppRadius {
  AppRadius._();

  static double get xs => 4.rs;
  static double get sm => 6.rs;
  static double get md => 8.rs;
  static double get lg => 12.rs;
  static double get xl => 16.rs;
  static double get xxl => 24.rs;

  static BorderRadius get card => BorderRadius.circular(lg);
  static BorderRadius get button => BorderRadius.circular(md);
  static BorderRadius get input => BorderRadius.circular(md);
  static BorderRadius get chip => BorderRadius.circular(sm);
  static BorderRadius get dialog => BorderRadius.circular(xl);
  static BorderRadius get badge => BorderRadius.circular(xs);
}

class AppSizes {
  AppSizes._();

  static double get iconSm => 14.rs;
  static double get iconMd => 18.rs;
  static double get iconLg => 24.rs;
  static double get iconXl => 32.rs;

  static double get buttonHeight => 44.rs;
  static double get inputHeight => 40.rs;
  static double get chipHeight => 28.rs;

  static double get cardMinWidth => 280.rs;
  static double get sidebarWidth => Responsive.wp(18).clamp(200.0, 320.0);
  static double get panelWidth => Responsive.wp(28).clamp(280.0, 500.0);

  static double get headerHeight => 56.rs;
  static double get toolbarHeight => 48.rs;
}

class AppElevation {
  AppElevation._();

  static List<BoxShadow> get none => [];
  static List<BoxShadow> card(Color color) => [
    BoxShadow(color: color.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
  ];
  static List<BoxShadow> elevated(Color color) => [
    BoxShadow(color: color.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 4)),
  ];
  static List<BoxShadow> floating(Color color) => [
    BoxShadow(color: color.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 8)),
  ];
}
