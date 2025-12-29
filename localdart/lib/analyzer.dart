import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart'; // for compute
import 'package:fftea/fftea.dart';

/// Represents a segment of the song (e.g. a beat).
class Beat {
  final int index;
  final double start;
  final double duration;
  final List<double> timbre;
  final List<double> pitch;
  final double loudnessMax;
  final double loudnessStart;
  final double confidence;

  // Graph connections
  List<Neighbor> neighbors = [];

  Beat({
    required this.index,
    required this.start,
    required this.duration,
    required this.timbre,
    required this.pitch,
    required this.loudnessMax,
    required this.loudnessStart,
    required this.confidence,
    List<Neighbor>? neighbors,
  }) {
     if (neighbors != null) {
         this.neighbors = neighbors;
     }
  }
}

class Neighbor {
  final int destIndex;
  final double distance;

  Neighbor({required this.destIndex, required this.distance});
}

class AudioFeatures {
  final List<Beat> beats;
  final int sampleRate;
  final int totalSamples;

  AudioFeatures(this.beats, this.sampleRate, this.totalSamples);
}

class Analyzer {
  static const Map<String, double> weights = {
    'timbre': 1.0,
    'pitch': 10.0,
    'loudness_start': 1.0,
    'loudness_max': 1.0,
    'duration': 100.0,
    'confidence': 1.0
  };

  /// Analyzes raw PCM data to extract beats and features (Runs in Isolate).
  static Future<AudioFeatures> analyze(Int16List pcmData, int sampleRate) async {
    return compute(_analyzeIsolate, _AnalysisParams(pcmData, sampleRate));
  }

  static AudioFeatures _analyzeIsolate(_AnalysisParams params) {
    final pcmData = params.pcmData;
    final sampleRate = params.sampleRate;

    // 1. Beat Tracking / Segmentation
    List<int> beatOnsets = _detectBeats(pcmData, sampleRate);

    List<Beat> beats = [];

    // FFT setup
    const int fftSize = 1024;
    final stft = STFT(fftSize, Window.hanning(fftSize));

    for (int i = 0; i < beatOnsets.length - 1; i++) {
      int startSample = beatOnsets[i];
      int endSample = beatOnsets[i+1];

      if (endSample - startSample < fftSize) continue;

      // Extract features for this segment
      int mid = (startSample + endSample) ~/ 2;
      int windowStart = mid - (fftSize ~/ 2);
      if (windowStart < 0) windowStart = 0;
      if (windowStart + fftSize > pcmData.length) windowStart = pcmData.length - fftSize;

      List<double> chunk = pcmData.sublist(windowStart, windowStart + fftSize).map((e) => e.toDouble() / 32768.0).toList();

      final spectrum = stft.run(chunk).magnitudes();

      // MFCC (Simplified 12 coefficients)
      List<double> timbre = _computeMFCC(spectrum, sampleRate, 12);

      // Chroma (12 pitch classes)
      List<double> pitch = _computeChroma(spectrum, sampleRate);

      // Loudness
      double rms = _computeRMS(chunk);
      double loudness = 20 * (log(rms + 1e-9) / ln10);

      beats.append(Beat(
        index: i,
        start: startSample / sampleRate,
        duration: (endSample - startSample) / sampleRate,
        timbre: timbre,
        pitch: pitch,
        loudnessMax: loudness,
        loudnessStart: loudness,
        confidence: 1.0,
      ));
    }

    return AudioFeatures(beats, sampleRate, pcmData.length);
  }

  static List<int> _detectBeats(Int16List pcm, int sr) {
    // Very simple onset detection: RMS Envelope + Peak picking
    int windowSize = sr ~/ 50; // 20ms
    List<double> envelope = [];

    for (int i = 0; i < pcm.length; i += windowSize) {
      double sum = 0;
      int count = 0;
      for (int j = 0; j < windowSize && i+j < pcm.length; j++) {
        double val = pcm[i+j] / 32768.0;
        sum += val * val;
        count++;
      }
      envelope.add(sqrt(sum / count));
    }

    // Pick peaks with min distance of ~0.3s
    int minBeatDist = (0.3 * 50).toInt(); // in envelope frames
    List<int> onsets = [];
    onsets.add(0);

    int lastPeak = 0;
    for (int i = 1; i < envelope.length - 1; i++) {
      if (envelope[i] > envelope[i-1] && envelope[i] > envelope[i+1] && envelope[i] > 0.05) {
        if (i - lastPeak > minBeatDist) {
          onsets.add(i * windowSize);
          lastPeak = i;
        }
      }
    }
    onsets.add(pcm.length);
    return onsets;
  }

  static List<double> _computeMFCC(List<double> spectrum, int sr, int nCoeffs) {
    // Simplified: Binning spectrum
    List<double> bands = List.filled(nCoeffs, 0.0);
    int binSize = spectrum.length ~/ nCoeffs;
    for (int i=0; i<nCoeffs; i++) {
        double sum = 0;
        for (int j=0; j<binSize; j++) {
            if (i*binSize + j < spectrum.length) {
                sum += spectrum[i*binSize + j];
            }
        }
        bands[i] = log(sum + 1e-9);
    }
    return bands;
  }

  static List<double> _computeChroma(List<double> spectrum, int sr) {
    List<double> chroma = List.filled(12, 0.0);
    int fftSize = (spectrum.length - 1) * 2;

    for (int i = 0; i < spectrum.length; i++) {
      double freq = i * sr / fftSize;
      if (freq < 27.5) continue;

      double midi = 69 + 12 * (log(freq/440.0) / ln2);
      int semitone = midi.round() % 12;
      chroma[semitone] += spectrum[i];
    }

    double maxVal = chroma.reduce(max);
    if (maxVal > 0) {
        for(int i=0; i<12; i++) chroma[i] /= maxVal;
    }
    return chroma;
  }

  static double _computeRMS(List<double> chunk) {
    double sum = 0;
    for(var x in chunk) sum += x*x;
    return sqrt(sum / chunk.length);
  }

  static double getSegDist(Beat b1, Beat b2) {
    double dTimbre = euclideanDist(b1.timbre, b2.timbre);
    double dPitch = euclideanDist(b1.pitch, b2.pitch);
    double dLoudStart = (b1.loudnessStart - b2.loudnessStart).abs();
    double dLoudMax = (b1.loudnessMax - b2.loudnessMax).abs();
    double dDur = (b1.duration - b2.duration).abs();
    double dConf = (b1.confidence - b2.confidence).abs();

    return dTimbre * weights['timbre']! +
           dPitch * weights['pitch']! +
           dLoudStart * weights['loudness_start']! +
           dLoudMax * weights['loudness_max']! +
           dDur * weights['duration']! +
           dConf * weights['confidence']!;
  }

  static double euclideanDist(List<double> v1, List<double> v2) {
    double sum = 0;
    for(int i=0; i<v1.length; i++) {
        double d = v1[i] - v2[i];
        sum += d*d;
    }
    return sqrt(sum);
  }

  /// Generates the graph connections. Returns the list of beats with updated neighbors.
  static Future<List<Beat>> generateGraph(List<Beat> beats, double threshold) async {
      return compute(_generateGraphIsolate, _GraphParams(beats, threshold));
  }

  static List<Beat> _generateGraphIsolate(_GraphParams params) {
    final beats = params.beats;
    final threshold = params.threshold;

    for (int i = 0; i < beats.length; i++) {
      // Clear existing neighbors if regenerating
      beats[i].neighbors = []; // Reassign to ensure clean state

      for (int j = 0; j < beats.length; j++) {
        if (i == j) continue;
        if (beats[i].index % 4 != beats[j].index % 4) continue;

        double dist = getSegDist(beats[i], beats[j]);
        if (dist < threshold) {
            beats[i].neighbors.add(Neighbor(destIndex: j, distance: dist));
        }
      }
    }
    return beats;
  }
}

class _AnalysisParams {
    final Int16List pcmData;
    final int sampleRate;
    _AnalysisParams(this.pcmData, this.sampleRate);
}

class _GraphParams {
    final List<Beat> beats;
    final double threshold;
    _GraphParams(this.beats, this.threshold);
}

extension ListAdd<T> on List<T> {
    void append(T val) => add(val);
}
