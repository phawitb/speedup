# SpeakUp

Flutter speaking-practice app with on-device Whisper transcription and a
server-side GPT-5 mini feedback pipeline.

## Run locally

Start the analysis backend first:

```bash
cd backend
npm start
```

Then run Flutter in another terminal:

```bash
flutter run
```

The default backend addresses are:

- iOS Simulator: `http://127.0.0.1:8787`
- Android Emulator: `http://10.0.2.2:8787`

For a physical device or deployed backend:

```bash
flutter run --dart-define=SPEAKUP_BACKEND_URL=https://api.example.com
```

The first transcription downloads the Whisper `base` model (about 142 MB).
After that, transcription runs locally on the device. Only transcript text and
delivery metrics are sent to the SpeakUp backend; microphone audio is not sent.

Keep `backend/.env` private. It is ignored by Git and must never be bundled into
the Flutter application.

## Verify

```bash
flutter analyze
flutter test
cd backend && node --env-file=.env --test
```
