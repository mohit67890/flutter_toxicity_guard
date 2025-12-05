import 'package:flutter/material.dart';
import 'package:local_toxicity_guard/local_toxicity_guard.dart';
import 'package:local_toxicity_guard/services/ToxicityGuard.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _localToxicityGuardPlugin = LocalToxicityGuard();
  final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Toxicity Validation')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextField(
                controller: _textController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Enter text',
                ),
                minLines: 3,
                maxLines: null,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  String text = _textController.text;
                  ToxicityResult? result = await _localToxicityGuardPlugin
                      .detectToxicity(text);

                  print('Toxicity Result: $result');
                },
                child: const Text('Validate'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
