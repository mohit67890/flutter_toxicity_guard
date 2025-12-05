# local_toxicity_guard Example

A simple Flutter app demonstrating how to use the `local_toxicity_guard` plugin for on-device toxicity detection.

## Features Demonstrated

- Basic text input field for user content
- Real-time toxicity detection on button press
- Display of toxicity results with category scores

## Running the Example

1. Navigate to the example directory:

   ```bash
   cd example
   ```

2. Get dependencies:

   ```bash
   flutter pub get
   ```

3. Run the app:
   ```bash
   flutter run
   ```

## How It Works

1. Enter text in the text field
2. Tap the "Validate" button
3. The app analyzes the text using the local toxicity detection model
4. Results are printed to the console showing:
   - Overall toxicity status
   - Individual category scores
   - Confidence levels

## Learn More

For detailed documentation and advanced usage, see the [main README](../README.md).
