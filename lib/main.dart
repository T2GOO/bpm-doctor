import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import 'dart:math';

void main() {
  runApp(const MyApp());
}

// ─────────────────────────────────────────
//  STYLE — Brutalist palette
// ─────────────────────────────────────────
class AppStyle {
  static const Color background    = Color(0xFF0A0A0A);
  static const Color textPrimary   = Color(0xFFF0F0F0);
  static const Color accent        = Color(0xFFC01C28);
  static const Color textSecondary = Color(0xFF555555);
  static const Color trackDark     = Color(0xFF1A1A1A);
  static const Color trackLight    = Color(0xFF222222);
  static const Color textDim       = Color(0xFF444444);
}

// Letter-spacing in Flutter is expressed in logical pixels: emSpacing × size.
TextStyle _mono({
  required double size,
  Color color = AppStyle.textPrimary,
  double emSpacing = 0.0,
  FontWeight weight = FontWeight.w700,
}) =>
    GoogleFonts.spaceMono(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: size * emSpacing,
    );

TextStyle _barlow({
  required double size,
  Color color = AppStyle.textPrimary,
  double height = 1.0,
}) =>
    GoogleFonts.barlowCondensed(
      fontSize: size,
      fontWeight: FontWeight.w900,
      color: color,
      height: height,
    );

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: AppStyle.background,
        sliderTheme: SliderThemeData(
          trackHeight: 2,
          activeTrackColor:   AppStyle.accent,
          inactiveTrackColor: AppStyle.trackLight,
          thumbColor:         AppStyle.accent,
          thumbShape:         const _DiamondThumbShape(size: 16),
          overlayShape:       SliderComponentShape.noOverlay,
          tickMarkShape:      SliderTickMarkShape.noTickMark,
          showValueIndicator: ShowValueIndicator.never,
        ),
      ),
      home: const BpmScreen(),
    );
  }
}


// ─────────────────────────────────────────
//  ALGORITHM — Energy flux + Autocorrelation
//
//  Step 1 — Energy flux (onset detection)
//    Frames of 50 ms (peak amplitude in dB from the record plugin).
//    Flux = max(0, E[n] - E[n-1]): only positive energy jumps.
//    The flux is smoothed with a short moving average.
//    An onset fires on a rising edge crossing the adaptive threshold:
//      threshold = median(recent flux) + sensitivityFactor * stddev(recent flux)
//    Sub-frame linear interpolation gives a finer onset timestamp,
//    which breaks the BPM quantization induced by frame snapping.
//    A refractory period prevents double-triggering on the same beat.
//
//  Step 2 — Autocorrelation on the onset signal
//    Build a binary signal at 10 ms resolution: 1 at onset times, 0 elsewhere.
//    Autocorrelate over the last `_acfWindowSec` seconds.
//    The strongest peak inside the BPM range (50–200 BPM, i.e. 300–1200 ms
//    lags) gives the inter-beat period and therefore the BPM.
//    On ties the smallest lag wins (avoids the half-tempo octave error).
// ─────────────────────────────────────────

class BpmScreen extends StatefulWidget {
  const BpmScreen({super.key});
  @override
  State<BpmScreen> createState() => _BpmScreenState();
}

class _BpmScreenState extends State<BpmScreen>
    with SingleTickerProviderStateMixin {

  // ── UI state
  int  bpm         = 0;
  bool isListening = false;
  bool _btnPressed = false;
  late final AnimationController _pulseController;

  // ── Slider parameters
  double _acfWindowSec = 6.0;   // 1..10, step 0.5
  double _sensitivity  = 50.0;  // 0..100, mapped to factor 0.3..3.0

  double get _sensitivityFactor => 0.3 + (_sensitivity / 100.0) * 2.7;

  // ── Audio
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Amplitude>? _subscription;

  // ── Energy flux
  static const int _frameMs      = 50;
  static const int _fluxHistory  = 40;   // ~2 s of flux history (40 * 50ms)
  static const int _smoothWindow = 3;    // ~150 ms flux smoothing
  static const int _refractoryMs = 180;  // min spacing between onsets (~333 BPM ceiling)

  double _prevEnergy       = double.nan;
  double _prevSmoothedFlux = 0.0;
  int    _lastOnsetMs      = 0;
  final List<double> _fluxBuffer   = [];
  final List<double> _smoothBuffer = [];

  final List<int> _onsetTimestamps = [];
  Timer? _acfTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      value: 1.0, // Start at primary colour; pulse forward(from: 0) flashes accent.
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _acfTimer?.cancel();
    _subscription?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────
  //  Audio
  // ──────────────────────────────────────────────

  Future<void> startListening() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) return;

    _prevEnergy        = double.nan;
    _prevSmoothedFlux  = 0.0;
    _lastOnsetMs       = 0;
    _fluxBuffer.clear();
    _smoothBuffer.clear();
    _onsetTimestamps.clear();

    await _recorder.startStream(const RecordConfig());

    _acfTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _calculateBpmByAutocorrelation();
    });

    final myStream =
        _recorder.onAmplitudeChanged(Duration(milliseconds: _frameMs));

    _subscription = myStream.listen((val) {
      if (val.current.isFinite && val.current > -100) {
        _processFrame(val.current);
      }
    });

    setState(() => isListening = true);
  }

  Future<void> stopListening() async {
    _acfTimer?.cancel();
    await _subscription?.cancel();
    await _recorder.stop();
    setState(() {
      isListening       = false;
      bpm               = 0;
      _onsetTimestamps.clear();
      _fluxBuffer.clear();
      _smoothBuffer.clear();
      _prevEnergy       = double.nan;
      _prevSmoothedFlux = 0.0;
      _lastOnsetMs      = 0;
    });
    _pulseController.value = 1.0; // reset to primary so "---" is white
  }

  // ──────────────────────────────────────────────
  //  Step 1 — Energy flux & onset detection
  // ──────────────────────────────────────────────

  void _processFrame(double energyDb) {
    if (_prevEnergy.isNaN) {
      _prevEnergy = energyDb;
      return;
    }

    final flux = max(0.0, energyDb - _prevEnergy);
    _prevEnergy = energyDb;

    _smoothBuffer.add(flux);
    if (_smoothBuffer.length > _smoothWindow) _smoothBuffer.removeAt(0);

    final smoothedFlux =
        _smoothBuffer.reduce((a, b) => a + b) / _smoothBuffer.length;

    _fluxBuffer.add(smoothedFlux);
    if (_fluxBuffer.length > _fluxHistory) _fluxBuffer.removeAt(0);

    final threshold = _adaptiveThreshold(_fluxBuffer);

    final now           = DateTime.now().millisecondsSinceEpoch;
    final timeSinceLast = now - _lastOnsetMs;

    if (_prevSmoothedFlux <= threshold &&
        smoothedFlux       >  threshold &&
        timeSinceLast      >= _refractoryMs) {

      final denom = smoothedFlux - _prevSmoothedFlux;
      final fraction = denom > 0
          ? ((threshold - _prevSmoothedFlux) / denom).clamp(0.0, 1.0)
          : 1.0;
      final onsetMs = now - ((1.0 - fraction) * _frameMs).round();

      _onsetTimestamps.add(onsetMs);
      _lastOnsetMs = onsetMs;

      final cutoff = now - (_acfWindowSec * 1000).toInt();
      _onsetTimestamps.removeWhere((t) => t < cutoff);
    }

    _prevSmoothedFlux = smoothedFlux;
  }

  double _adaptiveThreshold(List<double> values) {
    if (values.isEmpty) return 1.0;

    final sorted = List<double>.from(values)..sort();
    final median = sorted[sorted.length ~/ 2];

    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values.map((v) => pow(v - mean, 2)).reduce((a, b) => a + b) /
            values.length;
    final std = sqrt(variance);

    return median + _sensitivityFactor * std;
  }

  // ──────────────────────────────────────────────
  //  Step 2 — Autocorrelation on the onset signal
  // ──────────────────────────────────────────────

  void _calculateBpmByAutocorrelation() {
    if (_onsetTimestamps.length < 4) return;

    const int binMs = 10;
    final int winMs = (_acfWindowSec * 1000).toInt();
    final int nBins = winMs ~/ binMs;
    if (nBins <= 0) return;

    final signal = List<double>.filled(nBins, 0.0);
    final now    = DateTime.now().millisecondsSinceEpoch;

    for (final t in _onsetTimestamps) {
      final offset = now - t;
      if (offset >= 0 && offset < winMs) {
        final bin = (winMs - offset) ~/ binMs;
        if (bin >= 0 && bin < nBins) signal[bin] = 1.0;
      }
    }

    const int lagMinMs  = 300;
    const int lagMaxMs  = 1200;
    final int lagMinBin = lagMinMs ~/ binMs;
    final int lagMaxBin = lagMaxMs ~/ binMs;

    double bestCorr   = -1;
    int    bestLagBin = lagMinBin;

    for (int lag = lagMinBin; lag <= lagMaxBin && lag < nBins; lag++) {
      double corr  = 0;
      int    count = 0;
      for (int i = 0; i + lag < nBins; i++) {
        corr += signal[i] * signal[i + lag];
        count++;
      }
      if (count > 0) corr /= count;

      if (corr > bestCorr) {
        bestCorr   = corr;
        bestLagBin = lag;
      }
    }

    if (bestCorr <= 0) return;

    final lagMs  = bestLagBin * binMs;
    final newBpm = (60000 / lagMs).round();

    if (newBpm >= 50 && newBpm <= 200) {
      if (newBpm != bpm) _pulseController.forward(from: 0);
      setState(() {
        bpm = newBpm;
      });
    }
  }

  // ──────────────────────────────────────────────
  //  UI
  // ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppStyle.background,
      body: Stack(
        children: [
          const Positioned.fill(child: _DotPattern()),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                Expanded(child: _buildBpmBlock()),
                _buildParameters(),
                const SizedBox(height: 32),
                _buildButton(),
                const SizedBox(height: 44),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 56, 28, 0),
      child: Row(
        children: [
          Text(
            'BPM DOCTOR',
            style: _mono(size: 13, emSpacing: 0.3, color: AppStyle.accent),
          ),
          const Spacer(),
          Text(
            isListening ? '● REC' : '○ STOP',
            style: _mono(
              size: 11,
              emSpacing: 0.3,
              color: isListening ? AppStyle.accent : AppStyle.textDim,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBpmBlock() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BEATS PER MINUTE',
            style: _mono(
              size: 12,
              emSpacing: 0.4,
              color: AppStyle.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          AnimatedBuilder(
            animation: _pulseController,
            builder: (_, _) {
              final color = Color.lerp(
                AppStyle.accent,
                AppStyle.textPrimary,
                _pulseController.value,
              )!;
              return Text(
                bpm == 0 ? '---' : '$bpm',
                style: _barlow(size: 184, color: color, height: 0.85),
              );
            },
          ),
          const SizedBox(height: 4),
          Text(
            'BPM',
            style: _mono(size: 18, emSpacing: 0.3, color: AppStyle.textDim),
          ),
          const SizedBox(height: 24),
          _buildBpmProgress(),
        ],
      ),
    );
  }

  Widget _buildBpmProgress() {
    final fill = bpm == 0 ? 0.0 : ((bpm - 60) / 120).clamp(0.0, 1.0);
    return LayoutBuilder(builder: (ctx, constraints) {
      return SizedBox(
        height: 3,
        child: Stack(
          children: [
            Container(width: constraints.maxWidth, color: AppStyle.trackDark),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutExpo,
              width: constraints.maxWidth * fill,
              color: AppStyle.accent,
            ),
          ],
        ),
      );
    });
  }

  Widget _buildParameters() {
    final acfDisplay = _acfWindowSec.truncateToDouble() == _acfWindowSec
        ? '${_acfWindowSec.toInt()}s'
        : '${_acfWindowSec.toStringAsFixed(1)}s';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          _paramRow(
            label:   'FENÊTRE',
            display: acfDisplay,
            slider: Slider(
              value: _acfWindowSec,
              min: 1,
              max: 10,
              divisions: 18,
              onChanged: isListening
                  ? null
                  : (v) => setState(() => _acfWindowSec = v),
            ),
          ),
          const SizedBox(height: 20),
          _paramRow(
            label:   'SEUIL',
            display: '${_sensitivity.round()}',
            slider: Slider(
              value: _sensitivity,
              min: 0,
              max: 100,
              divisions: 100,
              onChanged: (v) => setState(() => _sensitivity = v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paramRow({
    required String label,
    required String display,
    required Widget slider,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                label,
                style: _mono(
                  size: 11,
                  emSpacing: 0.3,
                  color: AppStyle.textSecondary,
                ),
              ),
              Text(display, style: _barlow(size: 20)),
            ],
          ),
        ),
        slider,
      ],
    );
  }

  Widget _buildButton() {
    final active = isListening;
    final bgColor   = active ? AppStyle.accent : Colors.transparent;
    final textColor = active ? AppStyle.background : AppStyle.accent;
    final label     = active ? '■ STOP' : 'ÉCOUTER';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown:   (_) => setState(() => _btnPressed = true),
        onTapCancel: ()  => setState(() => _btnPressed = false),
        onTapUp: (_) {
          setState(() => _btnPressed = false);
          if (active) {
            stopListening();
          } else {
            startListening();
          }
        },
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: bgColor,
            border: Border.all(color: AppStyle.accent, width: 2),
          ),
          child: ClipRect(
            child: LayoutBuilder(builder: (ctx, constraints) {
              return Stack(
                alignment: Alignment.centerLeft,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    width: _btnPressed ? constraints.maxWidth : 0.0,
                    height: 64,
                    color: const Color(0x66C01C28), // accent at 40% alpha
                  ),
                  Center(
                    child: Text(
                      label,
                      style: _mono(
                        size: 15,
                        emSpacing: 0.4,
                        color: textColor,
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
//  Custom painters
// ─────────────────────────────────────────

class _DotPattern extends StatelessWidget {
  const _DotPattern();
  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _DotPatternPainter(),
        size: Size.infinite,
      ),
    );
  }
}

class _DotPatternPainter extends CustomPainter {
  static const double _step = 4.0;
  // White at 3% alpha (0.03 * 255 ≈ 8 → 0x08FFFFFF)
  static const Color _dotColor = Color(0x08FFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = _dotColor;
    for (double y = 0; y < size.height; y += _step) {
      for (double x = 0; x < size.width; x += _step) {
        canvas.drawRect(Rect.fromLTWH(x, y, 1, 1), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DiamondThumbShape extends SliderComponentShape {
  final double size;
  const _DiamondThumbShape({this.size = 16});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size(size, size);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final half = size / 2;
    final path = Path()
      ..moveTo(center.dx, center.dy - half)
      ..lineTo(center.dx + half, center.dy)
      ..lineTo(center.dx, center.dy + half)
      ..lineTo(center.dx - half, center.dy)
      ..close();
    canvas.drawPath(
      path,
      Paint()..color = sliderTheme.thumbColor ?? AppStyle.accent,
    );
  }
}
