//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import Combine
import Foundation
import SwiftUI

// MARK: - Audiobook Part Model

public struct AudiobookPart: Identifiable, Hashable, Sendable {
    public let id: String
    public let partNumber: Int
    public let title: String
    public let durationSeconds: Double
    public var positionSeconds: Double

    public init(
        id: String,
        partNumber: Int,
        title: String,
        durationSeconds: Double,
        positionSeconds: Double = 0.0
    ) {
        self.id = id
        self.partNumber = partNumber
        self.title = title
        self.durationSeconds = durationSeconds
        self.positionSeconds = positionSeconds
    }

    public var progress: Double {
        guard durationSeconds > 0 else { return 0 }
        return min(max(positionSeconds / durationSeconds, 0.0), 1.0)
    }

    public var durationFormatted: String {
        let total = Int(durationSeconds)
        let hours = total / 3600
        let mins = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        } else {
            return "\(mins)m"
        }
    }
}

// MARK: - Audiobook View Model

@MainActor
public final class AudiobookViewModel: ObservableObject {

    public let bookId: String
    @Published public var bookTitle: String
    @Published public var author: String
    @Published public var coverURL: URL?

    @Published public var parts: [AudiobookPart] = []
    @Published public var currentPartIndex: Int = 0
    @Published public var isPlaying: Bool = false
    @Published public var currentPartTime: Double = 0.0
    @Published public var playbackRate: Float = 1.0
    @Published public var sleepTimerMinutes: Int? = nil
    @Published public var sleepTimerSecondsRemaining: Int? = nil

    private var playbackCancellable: AnyCancellable?
    private var sleepTimerCancellable: AnyCancellable?

    private let availableRates: [Float] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    private let sleepOptions: [Int?] = [nil, 15, 30, 45, 60]

    public init(
        bookId: String,
        bookTitle: String,
        author: String,
        coverURL: URL? = nil,
        initialParts: [AudiobookPart] = []
    ) {
        self.bookId = bookId
        self.bookTitle = bookTitle
        self.author = author
        self.coverURL = coverURL

        if initialParts.isEmpty {
            self.parts = Self.sampleParts(for: bookId)
        } else {
            self.parts = initialParts
        }

        setupTimer()
    }

    public var currentPart: AudiobookPart? {
        guard currentPartIndex >= 0 && currentPartIndex < parts.count else { return nil }
        return parts[currentPartIndex]
    }

    public var totalDurationSeconds: Double {
        parts.reduce(0) { $0 + $1.durationSeconds }
    }

    public var totalElapsedSeconds: Double {
        var elapsed: Double = 0.0
        for i in 0..<parts.count {
            if i < currentPartIndex {
                elapsed += parts[i].durationSeconds
            } else if i == currentPartIndex {
                elapsed += currentPartTime
            }
        }
        return elapsed
    }

    public var totalCompletionPercentage: Double {
        guard totalDurationSeconds > 0 else { return 0 }
        return min(max((totalElapsedSeconds / totalDurationSeconds) * 100.0, 0.0), 100.0)
    }

    public var totalRemainingString: String {
        let remaining = max(totalDurationSeconds - totalElapsedSeconds, 0.0)
        let total = Int(remaining)
        let hours = total / 3600
        let mins = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(mins)m left total"
        } else {
            return "\(mins)m left total"
        }
    }

    // MARK: - Playback Actions

    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    public func play() {
        isPlaying = true
    }

    public func pause() {
        isPlaying = false
        saveProgress()
    }

    public func skip(seconds: Double) {
        let newTime = currentPartTime + seconds
        if let part = currentPart {
            if newTime < 0 {
                // Rewind into previous part if available
                if currentPartIndex > 0 {
                    currentPartIndex -= 1
                    let prevDuration = parts[currentPartIndex].durationSeconds
                    currentPartTime = max(prevDuration + newTime, 0)
                } else {
                    currentPartTime = 0
                }
            } else if newTime > part.durationSeconds {
                // Forward into next part if available
                if currentPartIndex < parts.count - 1 {
                    currentPartIndex += 1
                    currentPartTime = newTime - part.durationSeconds
                } else {
                    currentPartTime = part.durationSeconds
                    pause()
                }
            } else {
                currentPartTime = newTime
            }
        }
    }

    public func seekPart(to targetSeconds: Double) {
        if let part = currentPart {
            currentPartTime = min(max(targetSeconds, 0.0), part.durationSeconds)
        }
    }

    public func jumpToPart(index: Int) {
        guard index >= 0 && index < parts.count else { return }
        currentPartIndex = index
        currentPartTime = 0.0
        play()
    }

    public func cyclePlaybackSpeed() {
        if let idx = availableRates.firstIndex(of: playbackRate) {
            let nextIdx = (idx + 1) % availableRates.count
            playbackRate = availableRates[nextIdx]
        } else {
            playbackRate = 1.0
        }
    }

    public func cycleSleepTimer() {
        if let idx = sleepOptions.firstIndex(of: sleepTimerMinutes) {
            let nextIdx = (idx + 1) % sleepOptions.count
            sleepTimerMinutes = sleepOptions[nextIdx]
        } else {
            sleepTimerMinutes = nil
        }

        if let minutes = sleepTimerMinutes {
            sleepTimerSecondsRemaining = minutes * 60
        } else {
            sleepTimerSecondsRemaining = nil
        }
    }

    public func saveProgress() {
        if currentPartIndex < parts.count {
            parts[currentPartIndex].positionSeconds = currentPartTime
        }
    }

    // MARK: - Internal Timers

    private func setupTimer() {
        playbackCancellable = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.handlePlaybackTick()
            }

        sleepTimerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.handleSleepTimerTick()
            }
    }

    private func handlePlaybackTick() {
        guard isPlaying, let part = currentPart else { return }
        let delta = 0.5 * Double(playbackRate)
        if currentPartTime + delta < part.durationSeconds {
            currentPartTime += delta
            parts[currentPartIndex].positionSeconds = currentPartTime
        } else {
            // Part finished, advance to next part
            if currentPartIndex < parts.count - 1 {
                currentPartIndex += 1
                currentPartTime = 0.0
            } else {
                currentPartTime = part.durationSeconds
                pause()
            }
        }
    }

    private func handleSleepTimerTick() {
        guard let remaining = sleepTimerSecondsRemaining, remaining > 0 else { return }
        sleepTimerSecondsRemaining = remaining - 1
        if remaining - 1 == 0 {
            pause()
            sleepTimerMinutes = nil
            sleepTimerSecondsRemaining = nil
        }
    }

    // MARK: - Sample Data

    private static func sampleParts(for bookId: String) -> [AudiobookPart] {
        [
            AudiobookPart(id: "\(bookId)-p1", partNumber: 1, title: "Chapter 1: The Gathering Storm", durationSeconds: 1680, positionSeconds: 840),
            AudiobookPart(id: "\(bookId)-p2", partNumber: 2, title: "Chapter 2: The Sands of Arrakis", durationSeconds: 2100),
            AudiobookPart(id: "\(bookId)-p3", partNumber: 3, title: "Chapter 3: The Bene Gesserit", durationSeconds: 1950),
            AudiobookPart(id: "\(bookId)-p4", partNumber: 4, title: "Chapter 4: House Atreides", durationSeconds: 2400),
            AudiobookPart(id: "\(bookId)-p5", partNumber: 5, title: "Chapter 5: The Voice", durationSeconds: 1820),
            AudiobookPart(id: "\(bookId)-p6", partNumber: 6, title: "Chapter 6: Shadows on Caladan", durationSeconds: 2240)
        ]
    }
}
