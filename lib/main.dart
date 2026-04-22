import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';

void main() {
  runApp(const MyApp());
}

// ─────────────────────────────────────────
//  STYLE
// ─────────────────────────────────────────
class AppStyle {
  // Couleurs
  static const Color background     = Color.fromARGB(255, 255, 0, 183);
  static const Color surface        = Color(0xFF0028CC);
  static const Color textPrimary    = Color(0xFF000000);
  static const Color textSecondary  = Color(0xFF001A99);
  static const Color divider        = Color(0xFF000000);
  static const Color btnActive      = Colors.transparent;
  static const Color btnInactive    = Color(0xFF000000);
  static const Color btnBorder      = Color(0xFF000000);
  static const Color sliderActive   = Color(0xFF000000);
  static const Color sliderInactive = Color(0x44000000);

  // Typographie
  static TextStyle displayStyle({
    String type = "default",
    double fontSize = 18,
    FontWeight fontWeight = FontWeight.w600,
    Color color = AppStyle.textPrimary,
    double letterSpacing = 0,
  }) {
    switch (type) {
      case 'Main' : {
        return GoogleFonts.spaceMono(
          fontSize:      fontSize,
          fontWeight:    fontWeight,
          color:         color,
          letterSpacing: letterSpacing,
        );
      }
      default : {
        return GoogleFonts.spaceMono(
          fontSize:      fontSize,
          fontWeight:    fontWeight,
          color:         color,
          letterSpacing: letterSpacing,
        );
      }
    }
    
  }

  // Tailles
  static const double titleSize   = 22.0;
  static const double bpmSize     = 72.0;
  static const double labelSize   = 18.0;
  static const double statusSize  = 15.0;
  static const double btnRadius   = 40.0;
}
// ─────────────────────────────────────────

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        sliderTheme: SliderThemeData(
          activeTrackColor:   AppStyle.sliderActive,
          inactiveTrackColor: AppStyle.sliderInactive,
          thumbColor:         AppStyle.sliderActive,
          overlayColor:       AppStyle.sliderActive.withOpacity(0.1),
        ),
      ),
      home: const BpmScreen(),
    );
  }
}

class BpmScreen extends StatefulWidget {
  const BpmScreen({super.key});
  @override
  State<BpmScreen> createState() => _BpmScreenState();
}

class _BpmScreenState extends State<BpmScreen> {
  int    bpm          = 0;
  bool   isListening  = false;
  double _amplitude   = 0;
  double _threshold   = -20.0;
  bool   _aboveThreshold       = false;
  List<int>    _beatTimestamps  = [];
  List<double> _currentWindowSamples = [];

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Amplitude>? _subscription;
  Timer? _windowTimer;

  // Paramètres sliders
  double _windowDuration    = 1.0;  // secondes
  double _sensitivityFactor = 0.5;  // 0 → 1

  // ── Audio ──────────────────────────────

  Future<void> startListening() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) return;

    _recorder.startStream(RecordConfig());

    _windowTimer = Timer.periodic(
      Duration(milliseconds: (_windowDuration * 1000).toInt()),
      (_) {
        _processWindow();
        _currentWindowSamples = [];
      },
    );

    final myStream =
        _recorder.onAmplitudeChanged(const Duration(milliseconds: 100));

    _subscription = myStream.listen((val) {
      setState(() => _amplitude = val.current);
      if (val.current.isFinite && val.current > -100) {
        _currentWindowSamples.add(val.current);
        _detectBeat(val.current);
      }
    });

    setState(() => isListening = true);
  }

  Future<void> stopListening() async {
    _windowTimer?.cancel();
    await _subscription?.cancel();
    await _recorder.stop();
    setState(() {
      isListening  = false;
      bpm          = 0;
      _beatTimestamps        = [];
      _aboveThreshold        = false;
      _currentWindowSamples  = [];
      _threshold   = -20.0;
    });
  }

  void _processWindow() {
    if (_currentWindowSamples.length < 5) return;
    final moyenne = _currentWindowSamples.reduce((a, b) => a + b) /
        _currentWindowSamples.length;
    final maxVal =
        _currentWindowSamples.reduce((a, b) => a > b ? a : b);
    setState(() {
      _threshold =
          moyenne + _sensitivityFactor * (maxVal - moyenne);
    });
    final now = DateTime.now().millisecondsSinceEpoch;
    _beatTimestamps.removeWhere((t) => now - t > 5000);
    _calculateBpm();
  }

  void _detectBeat(double amplitude) {
    if (amplitude > _threshold && !_aboveThreshold) {
      _aboveThreshold = true;
      _beatTimestamps.add(DateTime.now().millisecondsSinceEpoch);
    } else if (amplitude <= _threshold) {
      _aboveThreshold = false;
    }
  }

  void _calculateBpm() {
    if (_beatTimestamps.length < 4) return;
    final intervals = <int>[];
    for (int i = 1; i < _beatTimestamps.length; i++) {
      intervals.add(_beatTimestamps[i] - _beatTimestamps[i - 1]);
    }
    final moyenne =
        intervals.reduce((a, b) => a + b) / intervals.length;
    final newBpm = (60000 / moyenne).round();
    if (newBpm > 40 && newBpm < 220) {
      setState(() => bpm = newBpm);
    }
  }

  // ── UI ────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppStyle.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Titre
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 28, 0, 16),
              child: Text(
                'TECHNO DOCTOR',
                style: AppStyle.displayStyle(
                  fontSize:      AppStyle.titleSize,
                  letterSpacing: 0,
                ),
              ),
            ),

            // ── Séparateur
            Container(
              height: 1.5,
              color: AppStyle.divider,
              margin: const EdgeInsets.symmetric(horizontal: 24),
            ),

            const SizedBox(height: 32),

            // ── BPM
            Text(
              bpm == 0 ? '--- BPM' : '$bpm BPM',
              style: AppStyle.displayStyle(
                  type : "Main",
                  fontSize:      AppStyle.bpmSize,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 6,
                ),
            ),

            const SizedBox(height: 40),

            // ── Sliders
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildVerticalSlider(
                  label:   'FENÊTRE',
                  value:   _windowDuration,
                  min:     1,
                  max:     5,
                  display: '${_windowDuration.toInt()}s',
                  onChanged: isListening
                      ? null
                      : (v) => setState(() => _windowDuration = v),
                ),
                const SizedBox(width: 48),
                _buildVerticalSlider(
                  label:   'SEUIL',
                  value:   _sensitivityFactor,
                  min:     0,
                  max:     1,
                  display: _sensitivityFactor.toStringAsFixed(2),
                  onChanged: (v) =>
                      setState(() => _sensitivityFactor = v),
                ),
              ],
            ),

            const Spacer(),

            // ── Bouton micro
            GestureDetector(
              onTap: isListening ? stopListening : startListening,
              child: Container(
                width:  AppStyle.btnRadius * 2,
                height: AppStyle.btnRadius * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isListening
                      ? AppStyle.btnActive
                      : AppStyle.btnInactive,
                  border: Border.all(
                    color: AppStyle.btnBorder,
                    width: 2.5,
                  ),
                ),
                child: Icon(
                  Icons.mic,
                  size:  38,
                  color: isListening
                      ? AppStyle.btnBorder
                      : AppStyle.background,
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Statut
            Text(
              isListening ? 'Silence s\'il vous plaît !' : 'Inspirez !',
              style: AppStyle.displayStyle(
                  fontSize:      AppStyle.statusSize,
                  letterSpacing: 0,
                ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildVerticalSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required String display,
    required ValueChanged<double>? onChanged,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: AppStyle.displayStyle(
                  fontSize:      AppStyle.labelSize,
                  letterSpacing: 0,
                ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 160,
          child: RotatedBox(
            quarterTurns: -1,
            child: Slider(
              value:     value,
              min:       min,
              max:       max,
              onChanged: onChanged,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          display,
          style: AppStyle.displayStyle(
                  fontSize:      AppStyle.labelSize,
                  letterSpacing: 6,
                ),
        ),
      ],
    );
  }
}