import 'package:local_toxicity_guard/services/toxicity_guard.dart';

import 'local_toxicity_guard_platform_interface.dart';

class LocalToxicityGuard {
  Future<String?> getPlatformVersion() {
    return LocalToxicityGuardPlatform.instance.getPlatformVersion();
  }

  Future<ToxicityResult?> detectToxicity(String text) async {
    try {
      return await ToxicityGuard.detectToxicity(text);
    } catch (e) {
      print('LocalToxicityGuard: Error analyzing text: $e');
    }
    return null;
  }
}
