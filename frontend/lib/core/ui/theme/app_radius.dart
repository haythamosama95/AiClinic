import 'package:flutter/material.dart';

/// Border-radius tokens matching the web design system.
abstract final class AppRadius {
  static const double sm = 4;
  static const double md = 6;
  static const double lg = 8;
  static const double xl = 12;
  static const double xxl = 16;
  static const double full = 9999;

  static BorderRadius get smAll => BorderRadius.circular(sm);
  static BorderRadius get mdAll => BorderRadius.circular(md);
  static BorderRadius get lgAll => BorderRadius.circular(lg);
  static BorderRadius get xlAll => BorderRadius.circular(xl);
  static BorderRadius get xxlAll => BorderRadius.circular(xxl);
  static BorderRadius get fullAll => BorderRadius.circular(full);
}
