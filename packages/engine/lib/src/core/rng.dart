import 'dart:convert' show utf8;
import 'dart:math' as math;

const int _mask32 = 0xFFFFFFFF;
const double _two32 = 4294967296.0;

/// Multiplies two 32-bit unsigned integers modulo 2^32.
///
/// Uses 16-bit halves so every intermediate product fits in 53 bits, which
/// keeps the result exact on the web (JS doubles) as well as on native.
int mul32(int a, int b) {
  a &= _mask32;
  b &= _mask32;
  final aLo = a & 0xFFFF;
  final aHi = a >> 16;
  final bLo = b & 0xFFFF;
  final bHi = b >> 16;
  final cross = (aLo * bHi + aHi * bLo) & 0xFFFF;
  return (aLo * bLo + (cross << 16)) & _mask32;
}

/// 32-bit FNV-1a hash of the UTF-8 encoding of [s].
int fnv1a32(String s) {
  var hash = 0x811C9DC5;
  for (final byte in utf8.encode(s)) {
    hash = mul32(hash ^ byte, 0x01000193);
  }
  return hash;
}

/// Stateless splitmix32 mixer: returns the 32-bit output for input [x].
int splitmix32(int x) {
  var z = (x + 0x9E3779B9) & _mask32;
  z = mul32(z ^ (z >> 16), 0x21F0AAAD);
  z = mul32(z ^ (z >> 15), 0x735A2D97);
  return z ^ (z >> 15);
}

int _rotl32(int x, int k) => ((x << k) | (x >> (32 - k))) & _mask32;

/// Snapshot of a [SeededRng]'s four 32-bit state words.
class RngState {
  const RngState(this.s0, this.s1, this.s2, this.s3);

  final int s0;
  final int s1;
  final int s2;
  final int s3;
}

/// Deterministic xoshiro128** generator on four 32-bit words.
///
/// All arithmetic is masked to 32 bits so sequences are identical on native
/// and web. Named child streams are derived from the parent's *seed* via
/// [fork], so forking never depends on how much the parent has consumed.
class SeededRng {
  /// Creates a generator from [seed] (masked to 32 bits).
  SeededRng(int seed) : _seed = seed & _mask32 {
    _s0 = splitmix32(_seed);
    _s1 = splitmix32((_seed + 1) & _mask32);
    _s2 = splitmix32((_seed + 2) & _mask32);
    _s3 = splitmix32((_seed + 3) & _mask32);
    if (_s0 == 0 && _s1 == 0 && _s2 == 0 && _s3 == 0) _s0 = 1;
  }

  final int _seed;
  late int _s0;
  late int _s1;
  late int _s2;
  late int _s3;

  /// Independent stream named [name]: `seed' = splitmix32(seed ^ fnv1a32(name))`.
  SeededRng fork(String name) => SeededRng(splitmix32(_seed ^ fnv1a32(name)));

  /// Next value in `0..0xFFFFFFFF`.
  int nextUint32() {
    final result = mul32(_rotl32(mul32(_s1, 5), 7), 9);
    final t = (_s1 << 9) & _mask32;
    _s2 ^= _s0;
    _s3 ^= _s1;
    _s1 ^= _s2;
    _s0 ^= _s3;
    _s2 ^= t;
    _s3 = _rotl32(_s3, 11);
    return result;
  }

  /// Unbiased integer in `0..maxExclusive-1` (rejection sampling).
  int nextInt(int maxExclusive) {
    if (maxExclusive <= 0 || maxExclusive > 0x100000000) {
      throw ArgumentError.value(
        maxExclusive,
        'maxExclusive',
        'must be in 1..2^32',
      );
    }
    final limit = 0x100000000 - (0x100000000 % maxExclusive);
    var r = nextUint32();
    while (r >= limit) {
      r = nextUint32();
    }
    return r % maxExclusive;
  }

  /// Uniform double in `[0, 1)`.
  double nextDouble() => nextUint32() / _two32;

  bool nextBool(double pTrue) => nextDouble() < pTrue;

  /// Normal deviate via Box-Muller; two fresh uniforms per call, no caching.
  double nextGaussian({double mean = 0, double sd = 1}) {
    var u1 = nextDouble();
    while (u1 == 0) {
      u1 = nextDouble();
    }
    final u2 = nextDouble();
    final z = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
    return mean + sd * z;
  }

  /// Poisson deviate: Knuth for `lambda < 30`, gaussian approximation above.
  int nextPoisson(double lambda) {
    if (lambda <= 0) return 0;
    if (lambda < 30) {
      final l = math.exp(-lambda);
      var k = 0;
      var p = 1.0;
      do {
        k++;
        p *= nextDouble();
      } while (p > l);
      return k - 1;
    }
    final g = nextGaussian(mean: lambda, sd: math.sqrt(lambda));
    return math.max(0, g.round());
  }

  /// Index drawn proportionally to [weights] (all `>= 0`, sum `> 0`).
  int weightedIndex(List<double> weights) {
    if (weights.isEmpty) throw ArgumentError('weights must not be empty');
    var sum = 0.0;
    for (final w in weights) {
      if (w < 0) throw ArgumentError('weights must be >= 0, got $w');
      sum += w;
    }
    if (sum <= 0) throw ArgumentError('weights must sum to > 0');
    final r = nextDouble() * sum;
    var acc = 0.0;
    for (var i = 0; i < weights.length; i++) {
      acc += weights[i];
      if (r < acc) return i;
    }
    // Floating-point fallthrough: last index with a positive weight.
    return weights.lastIndexWhere((w) => w > 0);
  }

  T pick<T>(List<T> items) => items[nextInt(items.length)];

  /// In-place Fisher-Yates shuffle.
  void shuffle<T>(List<T> items) {
    for (var i = items.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final tmp = items[i];
      items[i] = items[j];
      items[j] = tmp;
    }
  }

  RngState get state => RngState(_s0, _s1, _s2, _s3);

  void restore(RngState s) {
    _s0 = s.s0;
    _s1 = s.s1;
    _s2 = s.s2;
    _s3 = s.s3;
  }
}
