import 'package:flutter/foundation.dart';
import 'package:local_toxicity_guard/services/toxicity_guard.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'local_toxicity_guard_method_channel.dart';

abstract class LocalToxicityGuardPlatform extends PlatformInterface {
  /// Constructs a LocalToxicityGuardPlatform.
  LocalToxicityGuardPlatform() : super(token: _token);

  static final Object _token = Object();

  static LocalToxicityGuardPlatform _instance =
      MethodChannelLocalToxicityGuard();

  /// The default instance of [LocalToxicityGuardPlatform] to use.
  ///
  /// Defaults to [MethodChannelLocalToxicityGuard].
  static LocalToxicityGuardPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [LocalToxicityGuardPlatform] when
  /// they register themselves.
  static set instance(LocalToxicityGuardPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  bool _isInitialized = false;
  bool _isInitializing = false;

  /// Whether the toxicity detection is ready to use
  bool get isReady => _isInitialized;

  /// Initialize the toxicity detection model
  /// Call this early in your app lifecycle (e.g., in main() or app startup)
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    if (_isInitializing) {
      // Wait for ongoing initialization
      while (_isInitializing) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return _isInitialized;
    }

    _isInitializing = true;
    try {
      await ToxicityGuard.initialize();
      _isInitialized = true;
      if (kDebugMode) {
        print('ToxicityService: Model initialized successfully');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('ToxicityService: Failed to initialize model: $e');
      }
      _isInitialized = false;
      return false;
    } finally {
      _isInitializing = false;
    }
  }

  /// Analyze text for toxicity
  /// Returns null if the service is not initialized
  Future<ToxicityResult?> analyzeText(String text) async {
    if (!_isInitialized) {
      if (kDebugMode) {
        print(
          'ToxicityService: Service not initialized, attempting to initialize...',
        );
      }
      await initialize();
    }

    try {
      return await ToxicityGuard.detectToxicity(text);
    } catch (e) {
      if (kDebugMode) {
        print('ToxicityService: Error analyzing text: $e');
      }
    }
    // Return null explicitly when an error occurs or result unavailable
    return null;
  }

  /// Quick check if text is considered toxic
  /// Returns false if service is not available
  Future<bool> isToxic(String text, {double threshold = 0.5}) async {
    final chatThresholds = {
      'toxic': threshold,
      'insult': threshold,
      'severeToxic': threshold,
      'identityHate': threshold,
      'threat': threshold,
      'obscene': threshold,
    };

    final result = await analyzeText(text);

    double? toxicScore = result?.toxicScore;
    double? insultScore = result?.insultScore;
    double? severeToxicityScore = result?.severeToxicScore;
    double? identityHateScore = result?.identityHateScore;
    double? threatScore = result?.threatScore;
    double? obsceneScore = result?.obsceneScore;

    if (toxicScore == null ||
        insultScore == null ||
        severeToxicityScore == null ||
        identityHateScore == null ||
        threatScore == null ||
        obsceneScore == null) {
      return false; // Unable to determine toxicity
    }

    // Check if any score exceeds the threshold
    if (toxicScore >= chatThresholds['toxic']! ||
        insultScore >= chatThresholds['insult']! ||
        severeToxicityScore >= chatThresholds['severeToxic']! ||
        identityHateScore >= chatThresholds['identityHate']! ||
        threatScore >= chatThresholds['threat']! ||
        obsceneScore >= chatThresholds['obscene']!) {
      if (kDebugMode) {
        print('ToxicityService: Text is considered toxic');
      }
      return true;
    }

    return result?.isToxic ?? false;
  }

  /// Get detailed toxicity breakdown
  Future<Map<String, double>?> getDetailedAnalysis(String text) async {
    final result = await analyzeText(text);
    return result?.categoryScores;
  }
}
