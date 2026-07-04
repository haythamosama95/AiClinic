import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Preview locale and text direction for the design system dev page.
@immutable
class DevPreviewState {
  const DevPreviewState({this.direction = TextDirection.ltr, this.locale = 'en'});

  final TextDirection direction;
  final String locale;

  DevPreviewState copyWith({TextDirection? direction, String? locale}) {
    return DevPreviewState(direction: direction ?? this.direction, locale: locale ?? this.locale);
  }
}

class DevPreviewNotifier extends Notifier<DevPreviewState> {
  @override
  DevPreviewState build() => const DevPreviewState();

  void setDirection(TextDirection direction) {
    state = state.copyWith(direction: direction);
  }

  void setLocale(String locale) {
    state = state.copyWith(locale: locale);
  }
}

final devPreviewProvider = NotifierProvider<DevPreviewNotifier, DevPreviewState>(DevPreviewNotifier.new);
