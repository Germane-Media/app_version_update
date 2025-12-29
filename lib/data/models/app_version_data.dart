import 'package:flutter/foundation.dart';

class AppVersionData {
  String? localVersion;
  String? storeVersion;
  String? storeUrl;
  TargetPlatform? targetPlatform;

  AppVersionData({
    this.localVersion,
    this.storeVersion,
    this.storeUrl,
    this.targetPlatform,
  });
}
