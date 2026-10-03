// Biquad filters (RBJ Audio EQ Cookbook) and a soft limiter.
import Foundation

typealias Coefficients = (b0: Double, b1: Double, b2: Double, a0: Double, a1: Double, a2: Double)

struct Biquad {
  var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
  var z1: Float = 0, z2: Float = 0

  @inline(__always) mutating func run(_ x: Float) -> Float {
    let y = b0 * x + z1
    z1 = b1 * x - a1 * y + z2
    z2 = b2 * x - a2 * y
    return y
  }

  mutating func set(_ c: Coefficients) {
    b0 = Float(c.b0 / c.a0); b1 = Float(c.b1 / c.a0); b2 = Float(c.b2 / c.a0)
    a1 = Float(c.a1 / c.a0); a2 = Float(c.a2 / c.a0)
  }

  static func peak(_ f: Double, q: Double, db: Double, sr: Double) -> Coefficients {
    let A = pow(10, db / 40), w = 2 * .pi * f / sr, c = cos(w), al = sin(w) / (2 * q)
    return (1 + al * A, -2 * c, 1 - al * A, 1 + al / A, -2 * c, 1 - al / A)
  }

  static func lowShelf(_ f: Double, db: Double, sr: Double) -> Coefficients {
    let A = pow(10, db / 40), w = 2 * .pi * f / sr, c = cos(w), sA = 2 * sqrt(A) * sin(w) / 2 * sqrt(2)
    return (A * ((A + 1) - (A - 1) * c + sA), 2 * A * ((A - 1) - (A + 1) * c), A * ((A + 1) - (A - 1) * c - sA),
            (A + 1) + (A - 1) * c + sA, -2 * ((A - 1) + (A + 1) * c), (A + 1) + (A - 1) * c - sA)
  }

  static func highShelf(_ f: Double, db: Double, sr: Double) -> Coefficients {
    let A = pow(10, db / 40), w = 2 * .pi * f / sr, c = cos(w), sA = 2 * sqrt(A) * sin(w) / 2 * sqrt(2)
    return (A * ((A + 1) + (A - 1) * c + sA), -2 * A * ((A - 1) + (A + 1) * c), A * ((A + 1) + (A - 1) * c - sA),
            (A + 1) - (A - 1) * c + sA, 2 * ((A - 1) - (A + 1) * c), (A + 1) - (A - 1) * c - sA)
  }
}

/// Simple 3-band EQ: low shelf 160 Hz, wide bell 1 kHz, high shelf 6 kHz.
struct ThreeBandEQ {
  var bands = [[Biquad]](repeating: [Biquad](repeating: Biquad(), count: 2), count: 3)

  mutating func set(low: Double, mid: Double, high: Double, sr: Double) {
    for ch in 0..<2 {
      bands[0][ch].set(Biquad.lowShelf(160, db: low, sr: sr))
      bands[1][ch].set(Biquad.peak(1000, q: 0.7, db: mid, sr: sr))
      bands[2][ch].set(Biquad.highShelf(6000, db: high, sr: sr))
    }
  }

  @inline(__always) mutating func run(_ x: Float, _ ch: Int) -> Float {
    bands[2][ch].run(bands[1][ch].run(bands[0][ch].run(x)))
  }
}

/// Transparent below -0.4 dBFS, then a soft knee towards 0 dBFS.
@inline(__always) func softLimit(_ x: Float) -> Float {
  let a = abs(x)
  if a < 0.95 { return x }
  return (x < 0 ? -1 : 1) * (0.95 + 0.05 * tanh((a - 0.95) / 0.05))
}

func dbToGain(_ db: Double) -> Float { Float(pow(10, db / 20)) }
