//
//  ListeningStatsTests.swift
//  ResonaTests
//
//  Round 10 stats: aggregation, skips, streaks, periods, recap slides.
//

import XCTest
@testable import Trop

final class ListeningStatsTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func play(_ id: String, _ artist: String, album: String? = nil, day: Int, hour: Int, minutes: Double) -> StatsPlay {
        StatsPlay(songId: id, title: "Platzhalter \(id)", artist: artist, album: album, thumbnailUrl: nil,
                  timestamp: date(day, hour), playTime: Int64(minutes * 60_000))
    }

    func testAggregatesMinutesPlaysAndRankings() {
        let plays = [
            play("a", "Band Eins", album: "Album X", day: 5, hour: 22, minutes: 3),
            play("a", "Band Eins", album: "Album X", day: 5, hour: 23, minutes: 3),
            play("b", "Band Zwei", day: 6, hour: 8, minutes: 4),
            play("c", "band eins", album: "Album X", day: 7, hour: 22, minutes: 2),
            play("d", "Band Drei", day: 7, hour: 22, minutes: 0.2)   // skip
        ]
        let stats = ListeningStats.compute(plays, calendar: calendar)
        XCTAssertEqual(stats.totalMinutes, 12)
        XCTAssertEqual(stats.plays, 4)
        XCTAssertEqual(stats.distinctSongs, 3)
        XCTAssertEqual(stats.topSongs.first?.id, "a")
        XCTAssertEqual(stats.topSongs.first?.plays, 2)
        XCTAssertEqual(stats.topArtists.first?.title, "Band Eins")
        XCTAssertEqual(stats.topArtists.first?.minutes, 8)
        XCTAssertEqual(stats.topAlbums.first?.title, "Album X")
        XCTAssertEqual(stats.peakHour, 22)
        XCTAssertEqual(stats.longestStreakDays, 3)
        XCTAssertEqual(stats.firstPlay, date(5, 22))
        XCTAssertEqual(stats.weekdays.reduce(0, +), stats.hours.reduce(0, +))
    }

    func testEmptyStats() {
        let stats = ListeningStats.compute([], calendar: calendar)
        XCTAssertTrue(stats.isEmpty)
        XCTAssertNil(stats.peakHour)
        XCTAssertEqual(RecapSlide.slides(for: stats), [.intro, .summary])
    }

    func testStreakBreaksOnGap() {
        let days = Set([date(1, 0), date(2, 0), date(4, 0), date(5, 0), date(6, 0)].map { calendar.startOfDay(for: $0) })
        XCTAssertEqual(ListeningStats.longestStreak(days, calendar: calendar), 3)
    }

    func testWeekdayIndexIsMondayFirst() {
        // 2026-10-05 is a Monday.
        let stats = ListeningStats.compute([play("a", "Band", day: 5, hour: 12, minutes: 5)], calendar: calendar)
        XCTAssertEqual(stats.weekdays[0], 5)
    }

    func testPeriodStarts() {
        let now = date(20, 12)
        XCTAssertEqual(StatsPeriod.week.start(now: now, calendar: calendar), date(13, 12))
        XCTAssertEqual(StatsPeriod.year.start(now: now, calendar: calendar), calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!)
        XCTAssertEqual(StatsPeriod.allTime.start(now: now, calendar: calendar), .distantPast)
    }

    func testRecapSlidesForData() {
        let stats = ListeningStats.compute([play("a", "Band", day: 5, hour: 7, minutes: 4)], calendar: calendar)
        let slides = RecapSlide.slides(for: stats)
        XCTAssertEqual(slides.first, .intro)
        XCTAssertEqual(slides.last, .summary)
        XCTAssertTrue(slides.contains(.minutes))
        XCTAssertEqual(stats.listenerType, String(localized: "Early bird"))
    }
}
