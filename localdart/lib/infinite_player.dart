import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:infinite_jukebox/analyzer.dart';

class InfiniteAudioSource extends StreamAudioSource {
  final Int16List pcmData;
  final AudioFeatures features;
  final double branchProbability;

  Beat? currentBeat;
  int _samplePos = 0;
  final Random _rng = Random();

  InfiniteAudioSource({
    required this.pcmData,
    required this.features,
    this.branchProbability = 0.4,
  }) : super(tag: MediaItem(
      id: 'infinite_1',
      title: 'Infinite Stream',
      album: 'Local Jukebox',
      artUri: null,
  )) {
      if (features.beats.isNotEmpty) {
          currentBeat = features.beats[0];
          _samplePos = (currentBeat!.start * features.sampleRate).toInt();
      }
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    // If a range request comes for anything other than 0, we can't easily fulfill it
    // because our stream is dynamic.
    // However, players usually request 0- first.
    // We return a stream that pretends to be a very large WAV file.

    int offset = start ?? 0;

    // If offset is 0, we start fresh.
    // If offset > 0, we are in trouble unless we cache or track state.
    // For simplicity, we just ignore small probe offsets or throw if deep seek.
    // Actually, just_audio might proxy.

    return StreamAudioResponse(
      sourceLength: null,
      contentLength: null,
      offset: offset,
      stream: _streamAudio(offset),
      contentType: 'audio/wav',
    );
  }

  Stream<List<int>> _streamAudio(int offset) async* {
    // 1. WAV Header (44 bytes)
    List<int> header = _createWavHeader(features.sampleRate);

    if (offset < header.length) {
        yield header.sublist(offset);
    }

    // If offset was within header, we just yielded the rest.
    // If offset > header, we should technically skip bytes from the stream.
    // But since the stream is random, "skipping" 1000 bytes doesn't mean much
    // unless we mean "skipping 1000 bytes of the *current* generation".
    // We will just start generating from where we are.
    // This might cause a tiny glitch if the player expects byte-exact continuity
    // after a network drop, but for local proxy, it usually just reads linearly.

    int bufferSize = 4096;
    while (true) {
        if (currentBeat == null) break;

        // Determine segment end
        int endSample = ((currentBeat!.start + currentBeat!.duration) * features.sampleRate).toInt();

        // How much to read
        int remainingInBeat = endSample - _samplePos;
        if (remainingInBeat <= 0) {
            _nextBeat();
            continue;
        }

        int toRead = min(bufferSize ~/ 2, remainingInBeat); // 2 bytes per sample

        // Get sublist
        int pcmEnd = _samplePos + toRead;
        if (pcmEnd > pcmData.length) pcmEnd = pcmData.length;

        Int16List chunk = pcmData.sublist(_samplePos, pcmEnd);
        _samplePos += chunk.length;

        // Convert Int16 to bytes (Little Endian)
        Uint8List bytes = Uint8List(chunk.length * 2);
        for (int i = 0; i < chunk.length; i++) {
            int sample = chunk[i];
            bytes[i*2] = sample & 0xFF;
            bytes[i*2+1] = (sample >> 8) & 0xFF;
        }

        yield bytes;

        // If we finished the beat, decide next
        if (_samplePos >= endSample) {
            _nextBeat();
        }
    }
  }

  void _nextBeat() {
      if (currentBeat == null) return;

      // Logic for infinite jump
      if (currentBeat!.neighbors.isNotEmpty && _rng.nextDouble() < branchProbability) {
          Neighbor n = currentBeat!.neighbors[_rng.nextInt(currentBeat!.neighbors.length)];
          currentBeat = features.beats[n.destIndex];
          // Jump position
          _samplePos = (currentBeat!.start * features.sampleRate).toInt();
      } else {
          // Sequential
          int nextIdx = currentBeat!.index + 1;
          if (nextIdx < features.beats.length) {
              currentBeat = features.beats[nextIdx];
              // We are already at the correct samplePos technically if we just played through,
              // but explicit set ensures sync
               _samplePos = (currentBeat!.start * features.sampleRate).toInt();
          } else {
              // Loop to start
              currentBeat = features.beats[0];
              _samplePos = (currentBeat!.start * features.sampleRate).toInt();
          }
      }
  }

  List<int> _createWavHeader(int sampleRate) {
      var buffer = BytesBuilder();
      buffer.add(utf8Encode("RIFF"));
      buffer.add(int32(0x7FFFFFFF)); // Size (max)
      buffer.add(utf8Encode("WAVE"));
      buffer.add(utf8Encode("fmt "));
      buffer.add(int32(16)); // PCM chunk size
      buffer.add(int16(1)); // AudioFormat 1 = PCM
      buffer.add(int16(1)); // Channels 1
      buffer.add(int32(sampleRate));
      buffer.add(int32(sampleRate * 2)); // ByteRate
      buffer.add(int16(2)); // BlockAlign
      buffer.add(int16(16)); // BitsPerSample
      buffer.add(utf8Encode("data"));
      buffer.add(int32(0x7FFFFFFF)); // Data size (max)
      return buffer.toBytes();
  }

  List<int> int32(int v) {
      var b = Uint8List(4);
      ByteData.view(b.buffer).setInt32(0, v, Endian.little);
      return b;
  }

  List<int> int16(int v) {
      var b = Uint8List(2);
      ByteData.view(b.buffer).setInt16(0, v, Endian.little);
      return b;
  }

  List<int> utf8Encode(String s) => s.codeUnits;
}
