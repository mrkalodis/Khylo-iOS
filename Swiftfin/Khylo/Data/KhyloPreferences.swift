//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

import Foundation

public enum SubtitleMode: String, CaseIterable, Codable {
    case smart
    case alwaysOn
    case onlyForced
    case off
    case defaultMode
}

public enum KhyloPreferences {

    private static let suiteName = "khyloApp"
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    private enum Keys {
        static let maxBitrateIndex = "khylo_maxBitrateIndex"
        static let autoSkipIntros = "khylo_autoSkipIntros"
        static let autoSkipCredits = "khylo_autoSkipCredits"
        static let autoPlayNextEpisode = "khylo_autoPlayNextEpisode"
        static let preferredAudioLanguage = "khylo_preferredAudioLanguage"
        static let preferredSubtitleLanguage = "khylo_preferredSubtitleLanguage"
        static let subtitleMode = "khylo_subtitleMode"
        static let rememberAudioSubtitleSelections = "khylo_rememberAudioSubtitleSelections"
        static let hideWatchedInRecentlyAdded = "khylo_hideWatchedInRecentlyAdded"
        static let showMissingEpisodes = "khylo_showMissingEpisodes"
        static let showCollections = "khylo_showCollections"
    }

    /// Remember audio and subtitle track selections per item/series.
    public static var rememberAudioSubtitleSelections: Bool {
        get {
            defaults.object(forKey: Keys.rememberAudioSubtitleSelections) as? Bool ?? true
        }
        set {
            defaults.set(newValue, forKey: Keys.rememberAudioSubtitleSelections)
        }
    }

    /// Hide watched items in Recently Added section on Home.
    public static var hideWatchedInRecentlyAdded: Bool {
        get {
            defaults.object(forKey: Keys.hideWatchedInRecentlyAdded) as? Bool ?? false
        }
        set {
            defaults.set(newValue, forKey: Keys.hideWatchedInRecentlyAdded)
        }
    }

    /// Show missing episodes in TV season views.
    public static var showMissingEpisodes: Bool {
        get {
            defaults.object(forKey: Keys.showMissingEpisodes) as? Bool ?? false
        }
        set {
            defaults.set(newValue, forKey: Keys.showMissingEpisodes)
        }
    }

    /// Show curated collections row on Home screen.
    public static var showCollections: Bool {
        get {
            defaults.object(forKey: Keys.showCollections) as? Bool ?? true
        }
        set {
            defaults.set(newValue, forKey: Keys.showCollections)
        }
    }

    /// 0=Auto, 1=120Mbps, 2=80Mbps, 3=40Mbps, 4=20Mbps, 5=10Mbps, 6=1.5Mbps Data Saver
    public static var maxBitrateIndex: Int {
        get {
            defaults.object(forKey: Keys.maxBitrateIndex) as? Int ?? 0
        }
        set {
            defaults.set(newValue, forKey: Keys.maxBitrateIndex)
        }
    }

    /// Automatically skip intro markers during playback.
    public static var autoSkipIntros: Bool {
        get {
            defaults.object(forKey: Keys.autoSkipIntros) as? Bool ?? true
        }
        set {
            defaults.set(newValue, forKey: Keys.autoSkipIntros)
        }
    }

    /// Automatically skip end credits markers during playback.
    public static var autoSkipCredits: Bool {
        get {
            defaults.object(forKey: Keys.autoSkipCredits) as? Bool ?? true
        }
        set {
            defaults.set(newValue, forKey: Keys.autoSkipCredits)
        }
    }

    /// Automatically advance to and play the next episode.
    public static var autoPlayNextEpisode: Bool {
        get {
            defaults.object(forKey: Keys.autoPlayNextEpisode) as? Bool ?? true
        }
        set {
            defaults.set(newValue, forKey: Keys.autoPlayNextEpisode)
        }
    }

    /// Preferred audio language (ISO 639-2 format, default "eng").
    public static var preferredAudioLanguage: String {
        get {
            defaults.string(forKey: Keys.preferredAudioLanguage) ?? "eng"
        }
        set {
            defaults.set(newValue, forKey: Keys.preferredAudioLanguage)
        }
    }

    /// Preferred subtitle language (ISO 639-2 format, default "eng").
    public static var preferredSubtitleLanguage: String {
        get {
            defaults.string(forKey: Keys.preferredSubtitleLanguage) ?? "eng"
        }
        set {
            defaults.set(newValue, forKey: Keys.preferredSubtitleLanguage)
        }
    }

    /// Subtitle display mode.
    public static var subtitleMode: SubtitleMode {
        get {
            guard let raw = defaults.string(forKey: Keys.subtitleMode),
                  let mode = SubtitleMode(rawValue: raw) else {
                return .smart
            }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.subtitleMode)
        }
    }

    /// Resets all preferences stored in the suite to default values.
    public static func resetToDefaults() {
        defaults.removeObject(forKey: Keys.maxBitrateIndex)
        defaults.removeObject(forKey: Keys.autoSkipIntros)
        defaults.removeObject(forKey: Keys.autoSkipCredits)
        defaults.removeObject(forKey: Keys.autoPlayNextEpisode)
        defaults.removeObject(forKey: Keys.preferredAudioLanguage)
        defaults.removeObject(forKey: Keys.preferredSubtitleLanguage)
        defaults.removeObject(forKey: Keys.subtitleMode)
    }
}
