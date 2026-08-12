# SpeakUp analysis backend

Requires Node.js 20 or newer.

```bash
cp .env.example .env
# Add your project API key to .env
npm start
```

The Flutter app connects to `http://127.0.0.1:8787` on iOS Simulator and
`http://10.0.2.2:8787` on Android Emulator. Override it with:

```bash
flutter run --dart-define=SPEAKUP_BACKEND_URL=https://your-api.example.com
```

Never commit `.env` or put the OpenAI API key in the Flutter app.
