# SpeakUp analysis backend

Requires Node.js 20 or newer.

```bash
cp .env.example .env
# Add your Gemini API key to .env
npm start
```

The Flutter app connects to `http://127.0.0.1:8787`. For Android devices or
emulators, run `adb reverse tcp:8787 tcp:8787`. Override it with:

```bash
flutter run --dart-define=SPEAKUP_BACKEND_URL=https://your-api.example.com
```

Never commit `.env` or put the Gemini API key in the Flutter app.
