# 🩺 Techno Doctor

> Real-time BPM detection from microphone input — built with Flutter.

---

## What it does

Techno Doctor listens to your environment through the microphone and detects the BPM of any music playing around you. No tapping, no file import — just hold your phone up and read the tempo.

---

## How it works

1. **Calibration** — on each time window, the app samples the incoming amplitude and computes an adaptive threshold based on the average and peak levels
2. **Beat detection** — a beat is triggered when the amplitude crosses the threshold upward (rising edge only, no double-counting)
3. **BPM calculation** — intervals between the last detected beats are averaged and converted to BPM

The threshold recalibrates continuously, so the app adapts if the volume changes.

---

## Features

- 🎙️ Live microphone input
- 📊 Adaptive threshold — self-calibrates every N seconds
- 🎚️ Adjustable window duration (1–5s) and sensitivity factor via sliders
- 🔄 Auto-reset on stop
- 📱 Android support (tested on Pixel 9 Pro)

---

## Stack

| Layer | Technology |
|---|---|
| Framework | Flutter |
| Language | Dart |
| Audio capture | `record` ^6.0.0 |
| Permissions | `permission_handler` ^12.0.0 |

---

## Getting started

### Prerequisites

- Flutter SDK installed ([flutter.dev](https://flutter.dev/docs/get-started/install))
- Android device with USB debugging enabled
- Android SDK (via Android Studio)

### Run

```bash
git clone https://github.com/T2GOO/bpm-doctor.git
cd bpm-doctor
flutter pub get
flutter run
```

---

## Project structure

```
lib/
└── main.dart       # Full app — AppStyle, BpmScreen, audio logic
android/
└── app/src/main/
    └── AndroidManifest.xml   # RECORD_AUDIO permission
pubspec.yaml        # Dependencies
```

---

## Known limitations

- Amplitude-based detection only — no FFT or low-pass filtering yet
- Works best with music that has a clear, prominent kick drum
- Window slider is disabled while listening (requires restart to apply)

---

## Roadmap

- [ ] Low-pass filter (bass frequencies only)
- [ ] Tap tempo fallback
- [ ] BPM history graph
- [ ] iOS support

---

## License

MIT