import 'dart:io';

import 'package:flutter/foundation.dart';

const String continuumAppVersion = '0.1.0+1';

/// Build and runtime facts presented by Developer Tools.
class RuntimeEnvironmentInfo {
  const RuntimeEnvironmentInfo({
    required this.appVersion,
    required this.buildMode,
    required this.platform,
    required this.dartVersion,
  });

  factory RuntimeEnvironmentInfo.current() => RuntimeEnvironmentInfo(
        appVersion: continuumAppVersion,
        buildMode: kReleaseMode
            ? 'Release'
            : kProfileMode
                ? 'Profile'
                : 'Debug',
        platform:
            '${Platform.operatingSystem} · ${Platform.operatingSystemVersion}',
        dartVersion: Platform.version.split(' ').first,
      );

  final String appVersion;
  final String buildMode;
  final String platform;
  final String dartVersion;
}
