import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {
  GenerativeModel? _model;

  void initialize(String apiKey) {
    _model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        temperature: 0.7,
        maxOutputTokens: 600,
      ),
    );
  }

  bool get isInitialized => _model != null;

  Future<String> getStressRecommendations({
    required int stressScore,
    required String stressLabel,
    String? emotion,
  }) async {
    if (_model == null) {
      throw Exception(
        'Gemini not initialized. Please add your API key to the .env file.',
      );
    }

    final emotionContext = emotion != null
        ? 'The user\'s detected emotion is $emotion.'
        : '';

    final prompt =
        '''
You are a compassionate mental wellness coach. The user's current stress level is $stressScore/100 ($stressLabel). $emotionContext

Provide exactly 3 practical, specific, and actionable stress-relief recommendations. Format your response as follows:

🧘 **Tip 1: [Short Title]**
[2-3 sentence description of the technique]

💚 **Tip 2: [Short Title]**
[2-3 sentence description of the technique]

🌟 **Tip 3: [Short Title]**
[2-3 sentence description of the technique]

Keep the tone warm, encouraging, and supportive. Tailor the intensity of the recommendations to the stress level (gentle for low stress, more active interventions for high stress).
''';

    final response = await _model!.generateContent([Content.text(prompt)]);
    return response.text ?? 'Unable to generate recommendations at this time.';
  }

  Future<String> chat(String message, int currentStressScore) async {
    if (_model == null) {
      throw Exception('Gemini not initialized.');
    }

    final prompt =
        '''
You are a compassionate mental wellness assistant. The user's current stress score is $currentStressScore/100.
User says: "$message"

Respond helpfully and empathetically in 2-3 sentences. If relevant, relate your response to their stress level.
''';

    final response = await _model!.generateContent([Content.text(prompt)]);
    return response.text ?? 'I\'m here to help. Could you tell me more?';
  }
}
