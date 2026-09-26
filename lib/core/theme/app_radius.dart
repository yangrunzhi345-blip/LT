import 'package:flutter/widgets.dart';

class AppRadius {
  AppRadius._();

  static const double xs = 4;
  static const double sm = 6;
  static const double md = 8;
  static const double control = 10;
  static const double lg = 12;
  static const double container = 14;
  static const double xl = 16;
  static const double pill = 999;
  static const double full = 999;

  // ─── BorderRadius 辅助令牌 ───
  static final BorderRadius borderXs = BorderRadius.circular(xs);
  static final BorderRadius borderSm = BorderRadius.circular(sm);
  static final BorderRadius borderMd = BorderRadius.circular(md);
  static final BorderRadius borderControl = BorderRadius.circular(control);
  static final BorderRadius borderLg = BorderRadius.circular(lg);
  static final BorderRadius borderContainer = BorderRadius.circular(container);
  static final BorderRadius borderXl = BorderRadius.circular(xl);
  static final BorderRadius borderPill = BorderRadius.circular(pill);
}
