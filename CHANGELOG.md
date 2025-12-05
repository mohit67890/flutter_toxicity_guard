## 1.0.1

- Fixed typo in class name from TocixityGuard to ToxicityGuard
- Improved tokenization with punctuation handling
- Replaced print() with debugPrint() for better production logging
- Added constants for asset paths
- Removed unused config loading code
- Updated documentation and examples

## 1.0.0

- Initial stable release
- On-device toxicity detection using MiniLM-v2 ONNX model
- Support for 6 toxicity categories: toxic, severe_toxic, obscene, threat, insult, identity_hate
- ToxicityGuard class for direct detection
- ToxicityService singleton for app-wide management
- Adjustable threshold configuration
- Cross-platform support (Android & iOS)
- Privacy-first: 100% offline processing
