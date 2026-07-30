import SwiftUI

struct CollapsedView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject var nowPlaying: NowPlayingManager
    @ObservedObject var shelf: FileShelfModel
    @ObservedObject var pomodoro: PomodoroManager
    @ObservedObject var spectrum: SpectrumAnalyzer
    @ObservedObject private var settings = UserSettings.shared
    /// Whether the pill hero (cover-or-generic-icon + wave) should show at all —
    /// true for Spotify/Music, but also for any other system audio (browser
    /// video, calls, …) that has no scriptable track to show a cover for.
    let hasAudioHero: Bool
    /// True when `NotchRootView` draws the spectrum above the island so it can
    /// travel to the page as one object. The pill then reserves the run's space
    /// but leaves it empty — the width estimate in `collapsedWidth` still has to
    /// hold, or the capsule clips against its own silhouette.
    var waveDrawnByOverlay: Bool = false

    /// Icon and accent of whichever app is making the sound. Resolved centrally
    /// (once per bundle-ID change, not per wave-bar redraw) so the pill, the
    /// spectrum page and the fullscreen takeover all read the same answer.
    @ObservedObject private var sourceApp = SourceAppAccent.shared

    /// The colours this pill's wave and thumbnail draw with. See `WaveTints`.
    private var tints: WaveTints {
        WaveTints.resolve(nowPlaying: nowPlaying, sourceBundleID: spectrum.sourceBundleID, sourceAppTint: sourceApp.tint)
    }

    /// What VoiceOver says for the pill as a whole.
    ///
    /// One label on the container rather than labels on the parts: the pill is a
    /// cover thumbnail, a wave and sometimes a timer readout, none of which mean
    /// anything read out individually — "image, image, 24 colon 13" is worse than
    /// silence. Read as one sentence it is the same thing a sighted glance gets.
    private var spokenSummary: String {
        var parts: [String] = []
        if let track = nowPlaying.track, hasAudioHero {
            parts.append("\(track.name) — \(track.artist)")
        } else if hasAudioHero {
            parts.append(String(localized: "a11y.pill.audio", defaultValue: "Ton läuft"))
        }
        if let timer = pomodoro.pillText { parts.append(timer) }
        if !shelf.items.isEmpty {
            parts.append(String(localized: "a11y.pill.shelf", defaultValue: "\(shelf.items.count) Dateien in der Ablage"))
        }
        return parts.isEmpty
            ? String(localized: "a11y.pill.idle", defaultValue: "Côte d'OS")
            : parts.joined(separator: ", ")
    }

    var body: some View {
        let tints = self.tints
        // Spacings/paddings here must stay in lock-step with the width estimate
        // in `NotchViewModel.collapsedWidth`, or the pill clips against the
        // silhouette — so both sides read from the same `NotchLayout` constants.
        return HStack(spacing: NotchLayout.collapsedItemSpacing) {
            if hasAudioHero {
                if settings.pillSpectrumOnly {
                    // Spectrum-only mode: no thumbnail at all (neither cover
                    // nor source-app icon — "only the spectrum" holds for both
                    // kinds of audio), just the wave in the space the
                    // thumbnail freed up.
                    //
                    // Geometry is the spectrum *page* scaled down — one rule,
                    // one knob: the field keeps the page's aspect, so widening
                    // the pill also makes it taller and its bars thicker, and
                    // the run holds however many of those fit. That is why
                    // this reads like the page instead of like a stripe of
                    // hairlines. See `NotchLayout.pillSpectrumGeometry`.
                    let wave = NotchLayout.pillSpectrumGeometry(forWidth: settings.pillSpectrumWidth)
                    if waveDrawnByOverlay {
                        // The run itself is drawn above the island so it can
                        // travel to the page without ever unmounting; the pill
                        // only reserves its space here.
                        Color.clear
                            .frame(width: wave.runWidth, height: wave.frameHeight)
                    } else {
                        LiveWaveBarsView(
                            levels: spectrum.bands,
                            isLive: spectrum.isLive,
                            isActive: nowPlaying.screensAwake,
                            tint: tints.primary,
                            coverBars: tints.coverBars,
                            count: wave.barCount,
                            maxHeight: wave.waveHeight,
                            barWidth: wave.barWidth,
                            spacing: wave.spacing
                        )
                        .frame(width: wave.runWidth, height: wave.frameHeight)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    }
                } else if tints.fromCover, let url = nowPlaying.track?.artworkURL {
                    // Fade the new cover in (transaction animation) over a placeholder
                    // tinted to the track's accent colour rather than flat grey, so a
                    // track change doesn't flash a grey square then pop during the
                    // hero crossfade.
                    AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            nowPlaying.artworkColor ?? Color.white.opacity(0.1)
                        }
                    }
                    .frame(width: NotchLayout.collapsedArtworkWidth, height: NotchLayout.collapsedArtworkWidth)
                    .clipShape(RoundedRectangle(cornerRadius: NotchLayout.collapsedArtworkCornerRadius))
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
                } else {
                    // System audio with no scriptable track (browser video, a
                    // call, …) — show the source app's own icon full-bleed when
                    // we can identify it (no background/padding: app icons like
                    // Safari's already bake in their own rounding and margin, so
                    // wrapping them in another rounded-rect frame just shrank
                    // them further and read as an extra border), else fall back
                    // to a plain glyph on a tinted background.
                    Group {
                        if let icon = sourceApp.icon {
                            Image(nsImage: icon).resizable().scaledToFit()
                        } else {
                            RoundedRectangle(cornerRadius: NotchLayout.collapsedArtworkCornerRadius)
                                .fill(Color.white.opacity(0.1))
                                .overlay {
                                    Image(systemName: "waveform").font(.system(size: 11))
                                }
                        }
                    }
                    .frame(width: NotchLayout.collapsedArtworkWidth, height: NotchLayout.collapsedArtworkWidth)
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
                }
                if !settings.pillSpectrumOnly {
                    LiveWaveBarsView(
                        levels: spectrum.bands,
                        isLive: spectrum.isLive,
                        isActive: nowPlaying.screensAwake,
                        tint: tints.primary,
                        coverBars: tints.coverBars,
                        count: NotchLayout.collapsedWaveBarCount,
                        maxHeight: NotchLayout.collapsedWaveMaxHeight,
                        barWidth: NotchLayout.collapsedWaveBarWidth,
                        spacing: NotchLayout.collapsedWaveSpacing
                    )
                    .frame(width: NotchLayout.collapsedWavesWidth, height: NotchLayout.collapsedArtworkWidth)
                    .transition(.opacity)
                }
            } else if pomodoro.pillText == nil {
                // Idle glyph reflects the tab you'd return to, so it isn't
                // always the music icon when you last used another tab. Sized by
                // `TabIcon` itself — the same view the tab bar draws, so the two
                // cannot drift apart and the hard-cut handover keeps its premise.
                // (An outer `.font` here would be silently ignored; the one
                // inside `TabIcon` wins, being closer to the leaf.)
                TabIcon(tab: viewModel.selectedTab)
            }

            // The focus-timer readout joins to the right of the artwork + wave
            // while music plays and stands alone otherwise (it replaces the
            // idle glyph above rather than crowding it).
            if let readout = pomodoro.pillText {
                timerSegment(readout)
            }

            if !shelf.items.isEmpty {
                Label("\(shelf.items.count)", systemImage: "tray.full.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: NotchLayout.collapsedBadgeFontSize, weight: .semibold))
            }
        }
        .padding(.horizontal, NotchLayout.collapsedContentPadding)
        // Pin the pill row to a fixed top band. Without this the row is
        // vertically centered in the *animated* island frame during the morph,
        // so the glyph starts mid-island and drifts up — the diagonal flight.
        .frame(height: viewModel.collapsedHeight)
        .frame(maxHeight: .infinity, alignment: .top)
        // The spectrum-only toggle and its sliders swap the hero's layout in
        // place; a scoped value animation can't interfere with the staged
        // expand/collapse walk's explicit withAnimation calls.
        .animation(NotchLayout.islandMorphAnimation, value: settings.pillSpectrumOnly)
        .animation(NotchLayout.islandMorphAnimation, value: settings.pillSpectrumWidth)
        // One element, one sentence — see `spokenSummary`.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary)
    }

    /// The passive focus-timer readout. Sizes must stay in lock-step with the
    /// width estimate in `NotchViewModel.timerSegmentWidth`.
    private func timerSegment(_ readout: String) -> some View {
        let paused = pomodoro.phase == .paused
        return HStack(spacing: NotchLayout.collapsedTimerInnerSpacing) {
            Image(systemName: paused ? "pause.fill" : "timer")
                .font(.system(size: NotchLayout.collapsedTimerIconSize, weight: .semibold))
                .foregroundStyle(paused ? Color.white.opacity(0.55) : Color.orange)
                .frame(width: NotchLayout.collapsedTimerIconWidth)
            Text(readout)
                .font(.system(size: NotchLayout.collapsedTimerFontSize, weight: .semibold))
                .monospacedDigit()
                .opacity(paused ? 0.55 : 1)
        }
    }
}
