// Writes the Spacewise brag soundtrack: 120 BPM, A minor, 21 s, 48 kHz stereo WAV.
import Foundation

let sr = 48_000.0
let duration = 21.0
let n = Int(sr * duration)
var L = [Double](repeating: 0, count: n)
var R = [Double](repeating: 0, count: n)
let beat = 0.5

var seed: UInt64 = 0x5EED
func noise() -> Double {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return Double(Int64(bitPattern: seed >> 1) % 2_000_000) / 1_000_000 - 1
}
func idx(_ t: Double) -> Int { Int((t * sr).rounded()) }
func add(_ i: Int, _ v: Double, pan: Double = 0) {
    guard i >= 0 && i < n else { return }
    L[i] += v * (1 - max(0, pan)); R[i] += v * (1 + min(0, pan))
}

// Chords: one per bar (2 s). Am F C G.
let chords: [[Double]] = [
    [220.00, 261.63, 329.63],   // Am
    [174.61, 220.00, 261.63],   // F
    [261.63, 329.63, 392.00],   // C
    [196.00, 246.94, 293.66],   // G
]
let roots: [Double] = [110.00, 87.31, 130.81, 98.00]
func bar(_ t: Double) -> Int { t >= 20 ? 0 : Int(t / 2) % 4 }

// MARK: Kick (also drives the sidechain duck)
var duck = [Double](repeating: 1, count: n)
func kick(_ t0: Double, _ amp: Double) {
    let len = 0.32
    var phase = 0.0
    for k in 0..<idx(len) {
        let t = Double(k) / sr
        let f = 45 + 85 * exp(-t * 28)
        phase += 2 * .pi * f / sr
        let env = exp(-t * 9) * min(1, t * 2000)
        add(idx(t0) + k, sin(phase) * env * amp)
    }
    for k in 0..<idx(0.22) {
        let i = idx(t0) + k
        if i < n { duck[i] = min(duck[i], 1 - 0.55 * exp(-Double(k) / sr * 14)) }
    }
}

// MARK: Clap, hats, whoosh (band-limited noise)
func clap(_ t0: Double, _ amp: Double) {
    var lp = 0.0, hp = 0.0
    for k in 0..<idx(0.22) {
        let t = Double(k) / sr
        let x = noise()
        lp += 0.35 * (x - lp); let band = lp - hp; hp += 0.04 * (lp - hp)
        let env = (exp(-t * 26) + 0.5 * exp(-max(0, t - 0.012) * 40) * (t > 0.012 ? 1 : 0)) * min(1, t * 3000)
        add(idx(t0) + k, band * env * amp, pan: 0.1)
    }
}
func hat(_ t0: Double, _ amp: Double, pan: Double) {
    var prev = 0.0
    for k in 0..<idx(0.06) {
        let t = Double(k) / sr
        let x = noise(); let h = x - prev; prev = x
        add(idx(t0) + k, h * exp(-t * 70) * amp, pan: pan)
    }
}
func whoosh(into cut: Double, _ amp: Double) {
    let len = 0.42
    var lp = 0.0
    for k in 0..<idx(len) {
        let x = Double(k) / Double(idx(len))
        lp += (0.01 + 0.25 * x * x) * (noise() - lp)
        let env = pow(x, 2.2) * (1 - pow(x, 12))
        add(idx(cut - len) + k, lp * env * amp, pan: sin(x * .pi) * 0.3 - 0.15)
    }
}

// MARK: Tonal voices
func pluck(_ t0: Double, _ f: Double, _ amp: Double, pan: Double) {
    for k in 0..<idx(0.45) {
        let t = Double(k) / sr
        let env = exp(-t * 9) * min(1, t * 800)
        let v = sin(2 * .pi * f * t) + 0.3 * sin(4 * .pi * f * t) * exp(-t * 20)
        add(idx(t0) + k, v * env * amp, pan: pan)
    }
}
func blip(_ t0: Double, _ f0: Double, _ f1: Double, _ len: Double, _ amp: Double) {
    var phase = 0.0
    for k in 0..<idx(len) {
        let t = Double(k) / sr, x = t / len
        phase += 2 * .pi * (f0 + (f1 - f0) * easeOutQ(x)) / sr
        add(idx(t0) + k, sin(phase) * exp(-x * 5) * min(1, t * 1500) * amp)
    }
}
func easeOutQ(_ x: Double) -> Double { 1 - (1 - x) * (1 - x) }

// Pad: soft detuned saws through a one-pole low-pass that opens at the reveal.
var padLPL = 0.0, padLPR = 0.0
var padPhases = [Double](repeating: 0, count: 6)
for i in 0..<n {
    let t = Double(i) / sr
    let chord = chords[bar(t)]
    var vl = 0.0, vr = 0.0
    for (j, f) in chord.enumerated() {
        for d in 0..<2 {
            let detune = d == 0 ? 0.998 : 1.002
            let p = j * 2 + d
            padPhases[p] += f * detune / sr
            if padPhases[p] > 1 { padPhases[p] -= 1 }
            let saw = 2 * padPhases[p] - 1
            if d == 0 { vl += saw } else { vr += saw }
        }
    }
    let open = t < 3 ? 0.012 + 0.01 * t / 3 : (t < 20 ? 0.05 : 0.05 * exp(-(t - 20) * 1.5) + 0.01)
    padLPL += open * (vl - padLPL); padLPR += open * (vr - padLPR)
    let fadeIn = min(1, t / 0.6)
    let tail = t > 20 ? exp(-(t - 20) * 1.2) : 1
    L[i] += padLPL * 0.055 * fadeIn * tail
    R[i] += padLPR * 0.055 * fadeIn * tail
}

// Arpeggio: 8th notes over the chord, an octave up, alternating left/right.
let order = [0, 1, 2, 1, 0, 2, 1, 2]
var step = 0
var t = 0.0
while t < 20.0 - 1e-9 {
    let chord = chords[bar(t)]
    let f = chord[order[step % 8]] * 2
    let amp = t < 3 ? 0.07 : 0.085
    pluck(t, f, amp, pan: step % 2 == 0 ? -0.35 : 0.35)
    step += 1; t += beat / 2
}
// Final chord rings from 20.0 s.
for (j, f) in chords[0].enumerated() { pluck(20.0 + Double(j) * 0.02, f * 2, 0.09, pan: Double(j - 1) * 0.3) }

// Bass: 8th-note root pulses from the reveal.
t = 3.0
while t < 20.0 - 1e-9 {
    let f = roots[bar(t)]
    for k in 0..<idx(0.23) {
        let tt = Double(k) / sr
        let env = min(1, tt * 300) * exp(-tt * 6)
        let v = tanh(1.6 * sin(2 * .pi * f * tt)) + 0.3 * sin(2 * .pi * f * 2 * tt)
        add(idx(t) + k, v * env * 0.16)
    }
    t += beat / 2
}

// Drums.
t = 1.0
while t < 20.0 - 1e-9 { kick(t, t < 3 ? 0.42 : 0.55); t += beat }
kick(20.0, 0.5)
t = 3.0
while t < 20.0 - 1e-9 {
    let inBar = (t.truncatingRemainder(dividingBy: 2.0))
    if abs(inBar - 0.5) < 1e-6 || abs(inBar - 1.5) < 1e-6 { clap(t, 0.2) }
    hat(t + beat / 2, 0.05, pan: 0.3)
    t += beat
}
// Build into the reveal: 16th hats rising over the last beat of the hook.
for k in 0..<4 { hat(2.5 + Double(k) * 0.125, 0.025 + 0.012 * Double(k), pan: 0.2) }

// Effects, in key and under the music.
for cut in [3.0, 5.5, 9.5, 13.0, 15.5, 18.0] { whoosh(into: cut, 0.09) }
blip(3.0, 220, 440, 0.22, 0.09)          // icon pops in (A3 → A4)
blip(18.0, 220, 440, 0.22, 0.08)         // outro icon
blip(6.5, 1318.5, 1318.5, 0.035, 0.05)   // click on Home (E6)
blip(6.5, 659.25, 659.25, 0.05, 0.03)    // body of the click (E5)

// Mix: sidechain the tonal layers lightly via the duck curve, soft clip, fade the tail.
var peak = 0.0
for i in 0..<n {
    let tt = Double(i) / sr
    let d = tt >= 3 ? duck[i] : 1
    var l = L[i] * (0.75 + 0.25 * d), r = R[i] * (0.75 + 0.25 * d)
    l = tanh(l * 1.4) / tanh(1.4); r = tanh(r * 1.4) / tanh(1.4)
    let fade = tt > 20.6 ? max(0, (21.0 - tt) / 0.4) : 1
    L[i] = l * fade; R[i] = r * fade
    peak = max(peak, abs(L[i]), abs(R[i]))
}
let gain = 0.89 / peak   // about -1 dBFS

// WAV (16-bit PCM).
var data = Data()
func u32(_ v: UInt32) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 4)) }
func u16(_ v: UInt16) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 2)) }
data.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + n * 4)); data.append("WAVEfmt ".data(using: .ascii)!)
u32(16); u16(1); u16(2); u32(UInt32(sr)); u32(UInt32(sr) * 4); u16(4); u16(16)
data.append("data".data(using: .ascii)!); u32(UInt32(n * 4))
var pcm = [Int16](repeating: 0, count: n * 2)
for i in 0..<n {
    pcm[i * 2] = Int16(max(-32767, min(32767, L[i] * gain * 32767)))
    pcm[i * 2 + 1] = Int16(max(-32767, min(32767, R[i] * gain * 32767)))
}
pcm.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
try! data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("wrote \(CommandLine.arguments[1]), peak before gain \(peak)")
