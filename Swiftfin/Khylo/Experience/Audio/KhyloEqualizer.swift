//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import AVFoundation
import Combine
import MediaToolbox
import os
import SwiftUI

// MARK: - Settings

/// A ten-band graphic equalizer for music. The sound is shaped inside the
/// player as it plays, so changes are heard straight away.
@MainActor
final class KhyloEqualizer: ObservableObject {

    static let shared = KhyloEqualizer()

    /// Centre of each band, in hertz.
    nonisolated static let frequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let range: ClosedRange<Float> = -12 ... 12

    struct Preset: Identifiable, Equatable {
        let name: String
        let gains: [Float]
        var id: String { name }
    }

    static let presets: [Preset] = [
        Preset(name: "Flat", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        Preset(name: "Bass Boost", gains: [6, 5.5, 4.5, 2.5, 0.5, 0, 0, 0, 0, 0]),
        Preset(name: "Bass Reducer", gains: [-6, -5, -4, -2, -0.5, 0, 0, 0, 0, 0]),
        Preset(name: "Treble Boost", gains: [0, 0, 0, 0, 0, 1, 2.5, 4, 5, 6]),
        Preset(name: "Vocal", gains: [-2, -1.5, -0.5, 1.5, 3.5, 4, 3, 1.5, 0, -1]),
        Preset(name: "Rock", gains: [5, 4, 2.5, 0.5, -1, -1, 0.5, 2.5, 3.5, 4.5]),
        Preset(name: "Electronic", gains: [5, 4.5, 1.5, 0, -2, 1, 0.5, 1.5, 4, 5]),
        Preset(name: "Hip-Hop", gains: [5, 4.5, 2, 3, -1, -1, 1, 0, 1.5, 3]),
        Preset(name: "Acoustic", gains: [4, 3.5, 2.5, 1, 1.5, 1.5, 3, 3.5, 3, 2]),
        Preset(name: "Late Night", gains: [3, 2.5, 1, 0, -1.5, -1.5, 0, 1, 2, 2.5]),
    ]

    @Published var isOn: Bool { didSet { publish() } }
    @Published var gains: [Float] { didSet { publish() } }
    /// Overall level before the bands, to keep boosted bands from clipping.
    @Published var preamp: Float { didSet { publish() } }

    /// The preset these gains match, or nil for your own curve.
    var presetName: String? {
        Self.presets.first { $0.gains == gains }?.name
    }

    private init() {
        let defaults = UserDefaults.standard
        isOn = defaults.bool(forKey: "khylo.eq.on")
        let saved = defaults.array(forKey: "khylo.eq.gains") as? [Double]
        gains = saved?.count == Self.frequencies.count ? saved!.map(Float.init) : Array(repeating: 0, count: Self.frequencies.count)
        preamp = Float(defaults.double(forKey: "khylo.eq.preamp"))
        publish()
    }

    func apply(_ preset: Preset) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { gains = preset.gains }
        if !isOn { isOn = true }
    }

    func reset() {
        apply(Self.presets[0])
    }

    private func publish() {
        let defaults = UserDefaults.standard
        defaults.set(isOn, forKey: "khylo.eq.on")
        defaults.set(gains.map(Double.init), forKey: "khylo.eq.gains")
        defaults.set(Double(preamp), forKey: "khylo.eq.preamp")
        KhyloEQState.set(isOn: isOn, gains: gains, preamp: preamp)
    }

    /// Adds the equalizer to a song as it's loaded. Songs played from the phone
    /// and songs that stream as they are get it; it shapes them live.
    static func attach(to item: AVPlayerItem) {
        let asset = item.asset
        Task {
            guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
                  let tap = KhyloEQTap.make()
            else { return }
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.audioTapProcessor = tap
            let mix = AVMutableAudioMix()
            mix.inputParameters = [parameters]
            await MainActor.run { item.audioMix = mix }
        }
    }

    /// The combined response in decibels at a frequency, for drawing the curve.
    static func response(at frequency: Float, gains: [Float], sampleRate: Float = 48000) -> Float {
        var total: Float = 0
        for (index, gain) in gains.enumerated() where gain != 0 {
            let c = KhyloEQState.peaking(frequency: frequencies[index], gain: gain, sampleRate: sampleRate)
            let w = 2 * Float.pi * frequency / sampleRate
            // |H(e^jw)| of the biquad.
            let cos1 = cos(w), cos2 = cos(2 * w), sin1 = sin(w), sin2 = sin(2 * w)
            let numRe = c.b0 + c.b1 * cos1 + c.b2 * cos2
            let numIm = -(c.b1 * sin1 + c.b2 * sin2)
            let denRe = 1 + c.a1 * cos1 + c.a2 * cos2
            let denIm = -(c.a1 * sin1 + c.a2 * sin2)
            let magnitude = sqrt((numRe * numRe + numIm * numIm) / (denRe * denRe + denIm * denIm))
            total += 20 * log10(max(magnitude, 1e-6))
        }
        return total
    }
}

// MARK: - Shared state for the audio thread

/// The current settings, readable from the audio thread without waiting.
enum KhyloEQState {

    struct Snapshot {
        var isOn = false
        var gains: [Float] = []
        var preamp: Float = 0
        var version = 0
    }

    struct Coefficients {
        var b0: Float, b1: Float, b2: Float, a1: Float, a2: Float
    }

    private static let lock = OSAllocatedUnfairLock(initialState: Snapshot())

    static func set(isOn: Bool, gains: [Float], preamp: Float) {
        lock.withLock { state in
            state = Snapshot(isOn: isOn, gains: gains, preamp: preamp, version: state.version + 1)
        }
    }

    /// Nil when the settings are being changed right now (keep the old ones).
    static func snapshot() -> Snapshot? {
        lock.withLockIfAvailable { $0 }
    }

    /// A peaking filter (RBJ cookbook) for one band.
    static func peaking(frequency: Float, gain: Float, sampleRate: Float, q: Float = 1.1) -> Coefficients {
        let a = pow(10, gain / 40)
        let w0 = 2 * Float.pi * min(frequency, sampleRate * 0.45) / sampleRate
        let alpha = sin(w0) / (2 * q)
        let cosw = cos(w0)
        let a0 = 1 + alpha / a
        return Coefficients(
            b0: (1 + alpha * a) / a0,
            b1: (-2 * cosw) / a0,
            b2: (1 - alpha * a) / a0,
            a1: (-2 * cosw) / a0,
            a2: (1 - alpha / a) / a0
        )
    }
}

// MARK: - Audio tap

/// The filter that runs on each block of sound as the player plays it.
private final class KhyloEQTap {

    private var sampleRate: Float = 44100
    private var channels = 2
    private var isNonInterleaved = true
    private var isFloat = true
    private var version = -1
    private var isOn = false
    private var preampGain: Float = 1
    /// Active bands (gain ≠ 0) only.
    private var coefficients: [KhyloEQState.Coefficients] = []
    /// Filter memory: channel × band × (x1, x2, y1, y2).
    private var memory: [Float] = []

    static func make() -> MTAudioProcessingTap? {
        let context = KhyloEQTap()
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: UnsafeMutableRawPointer(Unmanaged.passRetained(context).toOpaque()),
            init: { _, clientInfo, storageOut in
                storageOut.pointee = clientInfo
            },
            finalize: { tap in
                Unmanaged<KhyloEQTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, _, format in
                let context = Unmanaged<KhyloEQTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                let description = format.pointee
                context.sampleRate = Float(description.mSampleRate)
                context.channels = Int(description.mChannelsPerFrame)
                context.isNonInterleaved = description.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
                context.isFloat = description.mFormatFlags & kAudioFormatFlagIsFloat != 0
                context.version = -1
            },
            unprepare: { _ in },
            process: { tap, frames, _, bufferList, framesOut, flagsOut in
                guard MTAudioProcessingTapGetSourceAudio(tap, frames, bufferList, flagsOut, nil, framesOut) == noErr else { return }
                let context = Unmanaged<KhyloEQTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                context.process(bufferList, frames: Int(framesOut.pointee))
            }
        )
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        guard status == noErr else {
            Unmanaged<KhyloEQTap>.fromOpaque(callbacks.clientInfo!).release()
            return nil
        }
        return tap
    }

    private func refresh() {
        guard let snapshot = KhyloEQState.snapshot(), snapshot.version != version else { return }
        version = snapshot.version
        isOn = snapshot.isOn
        preampGain = pow(10, snapshot.preamp / 20)
        coefficients = snapshot.gains.enumerated().compactMap { index, gain in
            guard gain != 0, index < KhyloEqualizer.frequencies.count,
                  KhyloEqualizer.frequencies[index] < sampleRate * 0.45
            else { return nil }
            return KhyloEQState.peaking(frequency: KhyloEqualizer.frequencies[index], gain: gain, sampleRate: sampleRate)
        }
        memory = Array(repeating: 0, count: max(channels, 1) * coefficients.count * 4)
    }

    private func process(_ bufferList: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        refresh()
        guard isOn, isFloat, frames > 0, !coefficients.isEmpty || preampGain != 1 else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)

        if isNonInterleaved {
            for (channel, buffer) in buffers.enumerated() where channel < channels {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                filter(data, count: frames, stride: 1, channel: channel)
            }
        } else if let buffer = buffers.first, let data = buffer.mData?.assumingMemoryBound(to: Float.self) {
            for channel in 0 ..< channels {
                filter(data + channel, count: frames, stride: channels, channel: channel)
            }
        }
    }

    private func filter(_ samples: UnsafeMutablePointer<Float>, count: Int, stride: Int, channel: Int) {
        let bands = coefficients.count
        memory.withUnsafeMutableBufferPointer { memory in
            for frame in 0 ..< count {
                let index = frame * stride
                var x = samples[index] * preampGain
                for band in 0 ..< bands {
                    let c = coefficients[band]
                    let base = (channel * bands + band) * 4
                    let y = c.b0 * x + c.b1 * memory[base] + c.b2 * memory[base + 1]
                        - c.a1 * memory[base + 2] - c.a2 * memory[base + 3]
                    memory[base + 1] = memory[base]
                    memory[base] = x
                    memory[base + 3] = memory[base + 2]
                    memory[base + 2] = y
                    x = y
                }
                // Keep boosted peaks from wrapping into harsh distortion.
                samples[index] = min(max(x, -1), 1)
            }
        }
    }
}

// MARK: - Equalizer screen

struct KhyloEqualizerView: View {

    @ObservedObject private var equalizer = KhyloEqualizer.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Toggle(isOn: $equalizer.isOn) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Equalizer")
                            .font(.system(size: 17, weight: .semibold))
                        Text(equalizer.isOn ? (equalizer.presetName ?? "Custom") : "Off")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(KhyloStyle.accent)

                curve
                    .frame(height: 90)
                    .opacity(equalizer.isOn ? 1 : 0.35)

                bands
                    .opacity(equalizer.isOn ? 1 : 0.45)
                    .disabled(!equalizer.isOn)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Preamp")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text(String(format: "%+.1f dB", equalizer.preamp))
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $equalizer.preamp, in: -12 ... 6, step: 0.5)
                        .tint(KhyloStyle.accent)
                    Text("Turn this down a little if strong boosts sound harsh.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .disabled(!equalizer.isOn)
                .opacity(equalizer.isOn ? 1 : 0.45)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Presets")
                        .font(.system(size: 15, weight: .semibold))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                        ForEach(KhyloEqualizer.presets) { preset in
                            let isSelected = equalizer.isOn && equalizer.presetName == preset.name
                            Button {
                                UISelectionFeedbackGenerator().selectionChanged()
                                equalizer.apply(preset)
                            } label: {
                                Text(preset.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(isSelected ? .black : .white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 36)
                                    .background(Capsule().fill(isSelected ? Color.white : Color.white.opacity(0.1)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Text("The equalizer shapes songs played from your iPhone and songs your server sends as they are. Songs your server converts on the fly play without it until they're cached on your iPhone.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .background(KhyloStyle.canvas.ignoresSafeArea())
        .navigationTitle("Equalizer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Reset") { equalizer.reset() }
                    .disabled(equalizer.gains.allSatisfy { $0 == 0 })
            }
        }
    }

    /// The overall shape of the sound, drawn from the band settings.
    private var curve: some View {
        Canvas { context, size in
            let midY = size.height / 2
            var grid = Path()
            grid.move(to: CGPoint(x: 0, y: midY))
            grid.addLine(to: CGPoint(x: size.width, y: midY))
            context.stroke(grid, with: .color(.white.opacity(0.15)), lineWidth: 1)

            let low = log10(Float(20)), high = log10(Float(20000))
            var path = Path()
            var fill = Path()
            fill.move(to: CGPoint(x: 0, y: midY))
            for step in 0 ... 120 {
                let x = CGFloat(step) / 120 * size.width
                let frequency = pow(10, low + (high - low) * Float(step) / 120)
                let db = KhyloEqualizer.response(at: frequency, gains: equalizer.gains)
                let y = midY - CGFloat(max(-15, min(15, db)) / 15) * (size.height / 2 - 4)
                if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                fill.addLine(to: CGPoint(x: x, y: y))
            }
            fill.addLine(to: CGPoint(x: size.width, y: midY))
            fill.closeSubpath()
            context.fill(fill, with: .linearGradient(
                Gradient(colors: [KhyloStyle.accent.opacity(0.35), KhyloStyle.accent.opacity(0.02)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)
            ))
            context.stroke(path, with: .color(KhyloStyle.accent), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.04)))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.easeOut(duration: 0.2), value: equalizer.gains)
    }

    private var bands: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(KhyloEqualizer.frequencies.indices, id: \.self) { index in
                VStack(spacing: 8) {
                    Text(String(format: "%+.0f", equalizer.gains[index]))
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                    KhyloBandSlider(value: $equalizer.gains[index])
                        .frame(height: 190)
                    Text(Self.label(KhyloEqualizer.frequencies[index]))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private static func label(_ frequency: Float) -> String {
        frequency >= 1000 ? "\(Int(frequency / 1000))k" : "\(Int(frequency))"
    }
}

/// One band: a vertical slider from −12 to +12 dB that fills from the middle.
private struct KhyloBandSlider: View {

    @Binding var value: Float
    @State private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let range = KhyloEqualizer.range
            let fraction = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let knobY = height * (1 - fraction)
            ZStack(alignment: .top) {
                Capsule()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 4)
                    .frame(maxWidth: .infinity)
                // Fill from the 0 dB line to the knob.
                Capsule()
                    .fill(KhyloStyle.accent)
                    .frame(width: 4, height: abs(knobY - height / 2))
                    .offset(y: min(knobY, height / 2))
                    .frame(maxWidth: .infinity)
                Rectangle()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 12, height: 1)
                    .offset(y: height / 2)
                Circle()
                    .fill(Color.white)
                    .frame(width: isDragging ? 22 : 18, height: isDragging ? 22 : 18)
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                    .offset(y: knobY - (isDragging ? 11 : 9))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        let fraction = 1 - min(max(gesture.location.y / height, 0), 1)
                        let raw = range.lowerBound + Float(fraction) * (range.upperBound - range.lowerBound)
                        let stepped = (raw * 2).rounded() / 2
                        if stepped != value {
                            if stepped == 0 { UISelectionFeedbackGenerator().selectionChanged() }
                            value = stepped
                        }
                    }
                    .onEnded { _ in isDragging = false }
            )
            .onTapGesture(count: 2) { value = 0 }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isDragging)
    }
}
