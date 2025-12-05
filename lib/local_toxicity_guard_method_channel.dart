import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'local_toxicity_guard_platform_interface.dart';

/// An implementation of [LocalToxicityGuardPlatform] that uses method channels.
class MethodChannelLocalToxicityGuard extends LocalToxicityGuardPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('local_toxicity_guard');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
