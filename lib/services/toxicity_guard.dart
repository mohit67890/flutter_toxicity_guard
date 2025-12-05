import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

class ToxicityGuard {
  static final OnnxRuntime _runtime = OnnxRuntime();
  static OrtSession? _session;
  static Map<String, int>? _tokenizer;
  static Map<String, dynamic>? _tokenizerConfig;
  static Map<String, dynamic>? _specialTokensMap;
  
  // One-time initialization future to prevent duplicate async work
  static Future<void>? _initialization;

  // Use optimized/quantized model for better performance (smaller and faster)
  static const bool _useOptimizedModel = false;
  
  static const String _baseAssetPath = 'packages/local_toxicity_guard/assets/toxicity_model';
  static const String _modelFileName = 'minilmv2_toxic_jigsaw.onnx';

  // Toxicity labels as defined in the model config
  static const List<String> _toxicityLabels = [
    'toxic',
    'severe_toxic',
    'obscene',
    'threat',
    'insult',
    'identity_hate',
  ];

  /// Public initialization entry point. Safe to call multiple times.
  /// The underlying heavy work runs only once and is cached in [_initialization].
  static Future<void> initialize() async => ensureInitialized();

  /// Ensures the model/session/tokenizer are loaded exactly once.
  /// Subsequent calls await the first initialization.
  static Future<void> ensureInitialized() {
    if (_session != null) {
      // Already initialized
      return Future.value();
    }
    return _initialization ??= _doInitialize();
  }

  static Future<void> _doInitialize() async {
    try {
      final sessionOptions = OrtSessionOptions();
      String assetFileName = '$_baseAssetPath/$_modelFileName';

      if (_useOptimizedModel) {
        // Logic to select optimized model if available
        // For now, falling back to standard model as per original logic
      }

      try {
        await rootBundle.load(assetFileName);
      } catch (e) {
        debugPrint('ToxicityGuard: Model file not found at $assetFileName: $e');
        _initialization = null;
        return;
      }

      _session = await _runtime.createSessionFromAsset(
        assetFileName,
        options: sessionOptions,
      );

      // Load all configuration files in parallel for speed
      await Future.wait([
        _loadVocabulary(),
        _loadTokenizerConfig(),
        _loadSpecialTokensMap(),
      ]);
    } catch (e) {
      debugPrint('ToxicityGuard: Error loading model: $e');
      // If initialization failed, allow retry on next call
      _initialization = null;
    }
  }

  static Future<void> _loadVocabulary() async {
    try {
      final vocabFile = await rootBundle.loadString('$_baseAssetPath/vocab.txt');
      final lines = vocabFile.split('\n');

      _tokenizer = <String, int>{};
      for (int i = 0; i < lines.length; i++) {
        final token = lines[i].trim();
        if (token.isNotEmpty) {
          _tokenizer![token] = i;
        }
      }
    } catch (e) {
      debugPrint('ToxicityGuard: Error loading vocabulary: $e');
      rethrow;
    }
  }

  static Future<void> _loadTokenizerConfig() async {
    try {
      final configFile = await rootBundle.loadString('$_baseAssetPath/tokenizer_config.json');
      _tokenizerConfig = jsonDecode(configFile);
    } catch (e) {
      debugPrint('ToxicityGuard: Warning: Could not load tokenizer config: $e');
      _tokenizerConfig = {
        'model_max_length': 512,
        'do_lower_case': true,
        'do_basic_tokenize': true,
        'clean_up_tokenization_spaces': true,
        'tokenize_chinese_chars': true,
        'strip_accents': null,
      };
    }
  }

  static Future<void> _loadSpecialTokensMap() async {
    try {
      final tokensFile = await rootBundle.loadString('$_baseAssetPath/special_tokens_map.json');
      _specialTokensMap = jsonDecode(tokensFile);
    } catch (e) {
      debugPrint('ToxicityGuard: Warning: Could not load special tokens map: $e');
      _specialTokensMap = {
        'cls_token': '[CLS]',
        'sep_token': '[SEP]',
        'pad_token': '[PAD]',
        'unk_token': '[UNK]',
        'mask_token': '[MASK]',
      };
    }
  }

  static Future<ToxicityResult> detectToxicity(String text) async {
    await ensureInitialized();
    if (_session == null || _tokenizer == null) {
      return ToxicityResult.error();
    }

    try {
      final tokens = _tokenizeText(text);
      final sequenceLength = tokens.length;

      final inputIds = await OrtValue.fromList(Int64List.fromList(tokens), [
        1,
        sequenceLength,
      ]);

      final attentionMaskData = Int64List.fromList(
        tokens.map((token) => token == 0 ? 0 : 1).toList(),
      );
      final attentionMask = await OrtValue.fromList(attentionMaskData, [
        1,
        sequenceLength,
      ]);

      final tokenTypeIds = await OrtValue.fromList(
        Int64List.fromList(List.filled(sequenceLength, 0)),
        [1, sequenceLength],
      );

      final inputs = <String, OrtValue>{
        'input_ids': inputIds,
        'attention_mask': attentionMask,
        'token_type_ids': tokenTypeIds,
      };

      Map<String, OrtValue> outputs = {};
      try {
        outputs = await _session!.run(inputs);
      } finally {
        await Future.wait(inputs.values.map((value) => value.dispose()));
      }

      if (outputs.isEmpty) {
        return ToxicityResult.error();
      }
      try {
        return await _processOutputs(outputs);
      } finally {
        await Future.wait(outputs.values.map((value) => value.dispose()));
      }
    } catch (e) {
      debugPrint('ToxicityGuard: Error during inference: $e');
      return ToxicityResult.error();
    }
  }

  static Future<ToxicityResult> _processOutputs(
    Map<String, OrtValue> outputs,
  ) async {
    try {
      final firstOutput = outputs.values.first;
      final logitsRaw = await firstOutput.asFlattenedList();
      if (logitsRaw.isEmpty) {
        debugPrint('ToxicityGuard: Error: Logits are null');
        return ToxicityResult.error();
      }

      final logits = logitsRaw.map((value) => (value as num).toDouble()).toList();
      final probabilities = _sigmoid(logits);

      final toxicityThreshold = 0.5;
      final isToxic = probabilities.any((prob) => prob > toxicityThreshold);
      final maxToxicityScore = probabilities.reduce(math.max);

      final Map<String, double> categoryScores = {};
      for (int i = 0; i < _toxicityLabels.length && i < probabilities.length; i++) {
        categoryScores[_toxicityLabels[i]] = probabilities[i];
      }

      return ToxicityResult(
        toxicProbability: maxToxicityScore,
        safeProbability: 1.0 - maxToxicityScore,
        isToxic: isToxic,
        categoryScores: categoryScores,
      );
    } catch (e) {
      debugPrint('ToxicityGuard: Error processing outputs: $e');
      return ToxicityResult.error();
    }
  }

  static List<int> _tokenizeText(String text) {
    final maxLength = _tokenizerConfig?['model_max_length'] ?? 512;
    final doLowerCase = _tokenizerConfig?['do_lower_case'] ?? true;

    final clsToken = _specialTokensMap?['cls_token'] ?? '[CLS]';
    final sepToken = _specialTokensMap?['sep_token'] ?? '[SEP]';
    final unkToken = _specialTokensMap?['unk_token'] ?? '[UNK]';
    final padToken = _specialTokensMap?['pad_token'] ?? '[PAD]';

    final clsId = _tokenizer![clsToken] ?? 101;
    final sepId = _tokenizer![sepToken] ?? 102;
    final unkId = _tokenizer![unkToken] ?? 100;
    final padId = _tokenizer![padToken] ?? 0;

    List<int> tokens = [clsId];

    String processedText = doLowerCase ? text.toLowerCase().trim() : text.trim();
    
    // Basic punctuation splitting (add spaces around punctuation)
    // This mimics basic tokenization in BERT
    processedText = processedText.replaceAllMapped(
      RegExp(r'([.,!?;:()\[\]{}"\-])'), 
      (match) => ' ${match.group(0)} '
    );

    final words = processedText.split(RegExp(r'\s+'));

    for (final word in words) {
      if (word.isEmpty) continue;
      if (tokens.length >= maxLength - 1) break;

      if (_tokenizer!.containsKey(word)) {
        tokens.add(_tokenizer![word]!);
      } else {
        final subwordTokens = _tokenizeSubword(word, unkId);
        for (final token in subwordTokens) {
          if (tokens.length >= maxLength - 1) break;
          tokens.add(token);
        }
      }
    }

    if (tokens.length < maxLength) {
      tokens.add(sepId);
    }

    while (tokens.length < maxLength) {
      tokens.add(padId);
    }

    return tokens.take(maxLength).toList();
  }

  static List<int> _tokenizeSubword(String word, int unkId) {
    List<int> tokens = [];
    String remaining = word;
    bool isBad = false;

    while (remaining.isNotEmpty) {
      String? bestSubword;
      int? bestId;
      
      // Greedy longest-match-first strategy
      for (int i = remaining.length; i > 0; i--) {
        String subword = remaining.substring(0, i);
        if (tokens.isNotEmpty) {
          subword = '##$subword';
        }
        
        if (_tokenizer!.containsKey(subword)) {
          bestSubword = subword;
          bestId = _tokenizer![subword];
          break;
        }
      }

      if (bestSubword == null) {
        isBad = true;
        break;
      }

      tokens.add(bestId!);
      remaining = remaining.substring(bestSubword.startsWith('##') ? bestSubword.length - 2 : bestSubword.length);
    }

    if (isBad) {
      return [unkId];
    }
    return tokens;
  }

  static List<double> _sigmoid(List<double> logits) {
    return logits.map((x) => 1.0 / (1.0 + math.exp(-x))).toList();
  }

  static Future<void> dispose() async {
    if (_session != null) {
      try {
        await _session!.close();
      } catch (e) {
        debugPrint('ToxicityGuard: Error disposing session: $e');
      }
      _session = null;
    }
    _initialization = null;
  }
}

class ToxicityResult {
  final double toxicProbability;
  final double safeProbability;
  final bool isToxic;
  final bool hasError;
  final Map<String, double> categoryScores;

  ToxicityResult({
    required this.toxicProbability,
    required this.safeProbability,
    required this.isToxic,
    this.hasError = false,
    this.categoryScores = const {},
  });

  factory ToxicityResult.error() {
    return ToxicityResult(
      toxicProbability: 0.0,
      safeProbability: 0.0,
      isToxic: false,
      hasError: true,
      categoryScores: {},
    );
  }

  double get toxicScore => categoryScores['toxic'] ?? 0.0;
  double get severeToxicScore => categoryScores['severe_toxic'] ?? 0.0;
  double get obsceneScore => categoryScores['obscene'] ?? 0.0;
  double get threatScore => categoryScores['threat'] ?? 0.0;
  double get insultScore => categoryScores['insult'] ?? 0.0;
  double get identityHateScore => categoryScores['identity_hate'] ?? 0.0;

  @override
  String toString() {
    return 'ToxicityResult(isToxic: $isToxic, toxicProbability: ${toxicProbability.toStringAsFixed(3)}, categoryScores: $categoryScores)';
  }
}