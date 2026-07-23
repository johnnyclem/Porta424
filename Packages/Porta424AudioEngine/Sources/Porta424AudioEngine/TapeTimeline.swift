import Foundation

// MARK: - Region model

/// One contiguous take on a tape track timeline.
public struct TapeRegion: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var url: URL
    /// Timeline start (seconds from zero).
    public var start: TimeInterval
    public var duration: TimeInterval
    /// Offset into the audio file when the region begins (seconds).
    public var fileOffset: TimeInterval
    public var gain: Float

    public init(
        id: UUID = UUID(),
        url: URL,
        start: TimeInterval,
        duration: TimeInterval,
        fileOffset: TimeInterval = 0,
        gain: Float = 1
    ) {
        self.id = id
        self.url = url
        self.start = start
        self.duration = duration
        self.fileOffset = fileOffset
        self.gain = gain
    }

    public var end: TimeInterval { start + duration }

    public var isValid: Bool { duration > 0.0005 }
}

/// Lightweight UI/engine snapshot for one of the four tape tracks.
public struct TapeTrackState: Codable, Equatable, Sendable {
    public var index: Int
    public var name: String
    public var regionCount: Int
    public var totalDuration: TimeInterval
    public var hasTape: Bool

    public init(index: Int, name: String, regions: [TapeRegion]) {
        self.index = index
        self.name = name
        self.regionCount = regions.count
        self.totalDuration = regions.map(\.end).max() ?? 0
        self.hasTape = !regions.isEmpty
    }
}

// MARK: - Legacy alias

/// Historical name — same fields as a basic region without id/offset.
public struct TrackSegment: Codable, Equatable, Sendable {
    public var url: URL
    public var start: TimeInterval
    public var duration: TimeInterval

    public init(url: URL, start: TimeInterval, duration: TimeInterval) {
        self.url = url
        self.start = start
        self.duration = duration
    }

    public init(_ region: TapeRegion) {
        self.url = region.url
        self.start = region.start
        self.duration = region.duration
    }

    public var asRegion: TapeRegion {
        TapeRegion(url: url, start: start, duration: duration)
    }
}

// MARK: - Punch / timeline ops

public enum TapeTimeline {
    /// Insert `incoming` as a punch over `regions`: split/trim anything that
    /// intersects `[incoming.start, incoming.end)`, then append and sort.
    public static func commit(_ incoming: TapeRegion, into regions: inout [TapeRegion]) {
        guard incoming.isValid else { return }

        let punchIn = incoming.start
        let punchOut = incoming.end
        var next: [TapeRegion] = []
        next.reserveCapacity(regions.count + 2)

        for region in regions where region.isValid {
            // Completely before punch
            if region.end <= punchIn + 0.0001 {
                next.append(region)
                continue
            }
            // Completely after punch
            if region.start >= punchOut - 0.0001 {
                next.append(region)
                continue
            }

            // Left fragment (before punch-in)
            if region.start < punchIn {
                var left = region
                left.duration = punchIn - region.start
                if left.isValid { next.append(left) }
            }

            // Right fragment (after punch-out)
            if region.end > punchOut {
                let cutIntoFile = (punchOut - region.start)
                var right = region
                right.id = UUID()
                right.start = punchOut
                right.fileOffset = region.fileOffset + cutIntoFile
                right.duration = region.end - punchOut
                if right.isValid { next.append(right) }
            }
            // Middle overlap is discarded (overwritten by punch).
        }

        next.append(incoming)
        next.sort { $0.start < $1.start }
        regions = next
    }

    /// Regions that still have audio at or after `position`, sorted by start.
    public static func playable(from regions: [TapeRegion], at position: TimeInterval) -> [TapeRegion] {
        regions
            .filter { $0.isValid && $0.end > position + 0.0005 }
            .sorted { $0.start < $1.start }
    }

    public static func trackStates(from all: [[TapeRegion]]) -> [TapeTrackState] {
        all.enumerated().map { i, regions in
            TapeTrackState(index: i + 1, name: "TRK \(i + 1)", regions: regions)
        }
    }
}
