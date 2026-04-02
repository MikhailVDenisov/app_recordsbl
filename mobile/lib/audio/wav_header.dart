import 'dart:math' as math;
import 'dart:typed_data';

/// Собирает PCM16 little-endian stereo в WAV (RIFF) при остановке записи.
Uint8List buildWavFromPcm({
  required Uint8List pcmBytes,
  required int sampleRate,
  required int numChannels,
  required int bitsPerSample,
}) {
  final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
  final blockAlign = numChannels * bitsPerSample ~/ 8;
  final dataSize = pcmBytes.length;
  final chunkSize = 36 + dataSize;

  final b = BytesBuilder(copy: false);
  void w(String s) => b.add(s.codeUnits);
  void u32(int v) {
    final bd = ByteData(4)..setUint32(0, v, Endian.little);
    b.add(bd.buffer.asUint8List());
  }

  void u16(int v) {
    final bd = ByteData(2)..setUint16(0, v, Endian.little);
    b.add(bd.buffer.asUint8List());
  }

  w('RIFF');
  u32(chunkSize);
  w('WAVE');
  w('fmt ');
  u32(16);
  u16(1);
  u16(numChannels);
  u32(sampleRate);
  u32(byteRate);
  u16(blockAlign);
  u16(bitsPerSample);
  w('data');
  u32(dataSize);
  b.add(pcmBytes);
  return b.takeBytes();
}

/// RMS по PCM16 (interleaved каналы).
double rmsPcm16(Uint8List chunk) {
  if (chunk.length < 2) return 0;
  final n = chunk.length ~/ 2;
  if (n == 0) return 0;
  var sum = 0.0;
  final bd = ByteData.sublistView(chunk);
  for (var i = 0; i < n; i++) {
    final s = bd.getInt16(i * 2, Endian.little) / 32768.0;
    sum += s * s;
  }
  return math.sqrt(sum / n);
}
