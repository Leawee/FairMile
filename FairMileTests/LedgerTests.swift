import PDFKit
import XCTest
@testable import FairMile

@MainActor
final class LedgerTests: XCTestCase {
    func testNormalMovementAddsPathMiles() {
        let first = sample(latitude: 0, time: 0)
        let second = sample(latitude: 0.001, time: 10)
        let acceptance = TrackMath.accept([first, second])
        XCTAssertEqual(acceptance.points.count, 2)
        XCTAssertEqual(acceptance.gapCount, 0)
        XCTAssertEqual(acceptance.meters, TrackMath.pathMeters(points: acceptance.points), accuracy: 0.01)
        XCTAssertGreaterThan(acceptance.milesThousandths, 0)
    }

    func testJitterAndTeleportAreDropped() {
        let start = sample(latitude: 0, time: 0)
        let jitter = sample(latitude: 0.00001, time: 2)
        let teleport = sample(latitude: 0.02, time: 3)
        let acceptance = TrackMath.accept([start, jitter, teleport])
        XCTAssertEqual(acceptance.points.count, 1)
        XCTAssertEqual(acceptance.meters, 0, accuracy: 0.01)
    }

    func testCoverageGapDoesNotAddStraightLineDistance() {
        let start = sample(latitude: 0, time: 0)
        let later = sample(latitude: 0.005, time: 80)
        let acceptance = TrackMath.accept([start, later])
        XCTAssertEqual(acceptance.points.count, 2)
        XCTAssertEqual(acceptance.gapCount, 1)
        XCTAssertEqual(acceptance.meters, 0, accuracy: 0.01)
        XCTAssertEqual(TrackMath.pathMeters(points: acceptance.points), 0, accuracy: 0.01)
        XCTAssertNotEqual(acceptance.points[0].segment, acceptance.points[1].segment)
    }

    func testBundledRatesMatchTheIRSTable() throws {
        let records = try RateBook.loadBundled()
        XCTAssertEqual(RateBook.match(category: .business, day: "2026-06-30", records: records)?.centsTenths, 725)
        XCTAssertEqual(RateBook.match(category: .business, day: "2026-07-01", records: records)?.centsTenths, 760)
        XCTAssertEqual(RateBook.match(category: .medical, day: "2026-06-30", records: records)?.centsTenths, 205)
        XCTAssertEqual(RateBook.match(category: .medical, day: "2026-07-01", records: records)?.centsTenths, 235)
        XCTAssertEqual(RateBook.match(category: .charity, day: "2026-06-30", records: records)?.centsTenths, 140)
        XCTAssertEqual(RateBook.match(category: .charity, day: "2026-07-01", records: records)?.centsTenths, 140)
        XCTAssertEqual(RateBook.match(category: .business, day: "2025-12-31", records: records)?.centsTenths, 700)
        XCTAssertNil(RateBook.match(category: .personal, day: "2026-07-01", records: records))
        XCTAssertNil(RateBook.match(category: .business, day: "2027-01-01", records: records))
    }

    func testCustomRateOverridesTheIRSRow() {
        let records = [
            RateRecord(id: UUID(), category: .business, startDay: "2026-01-01", endDay: "2026-06-30", centsTenths: 725, source: "IRS", notice: "IR-2025-128", createdAt: .distantPast),
            RateRecord(id: UUID(), category: .business, startDay: "2026-06-01", endDay: "2026-06-30", centsTenths: 800, source: "custom", notice: "", createdAt: Date())
        ]
        XCTAssertEqual(RateBook.match(category: .business, day: "2026-06-15", records: records)?.centsTenths, 800)
        XCTAssertEqual(RateBook.match(category: .business, day: "2026-05-01", records: records)?.centsTenths, 725)
    }

    func testDeductionUsesTheStartDateAndRoundsHalfUp() {
        let records = sampleRates()
        let trip = makeTrip(start: date(2026, 6, 30, 22), end: date(2026, 7, 1, 1), miles: 10_000)
        let priced = LedgerMath.price(trip, records: records)
        XCTAssertEqual(priced.match?.centsTenths, 725)
        XCTAssertEqual(priced.amountCents, 725)
        XCTAssertTrue(priced.explanation.contains("crosses midnight"))
        XCTAssertEqual(RateBook.amountCents(milesThousandths: 1_000, centsTenths: 725), 73)
        let personal = makeTrip(start: date(2026, 7, 1), end: date(2026, 7, 1, 13), miles: 5_000, category: .personal)
        XCTAssertEqual(LedgerMath.price(personal, records: records).amountCents, 0)
    }

    func testSplitAndMergeKeepReportedMiles() {
        var trip = makeTrip(start: date(2026, 7, 2), end: date(2026, 7, 2, 15), miles: 10_000)
        trip.track = [
            sample(latitude: 0, time: 0),
            sample(latitude: 0.01, time: 100),
            sample(latitude: 0.02, time: 200)
        ]
        trip.trimEnd = 2
        let parts = TripEdits.divide(total: 10_000, fraction: 0.25)
        XCTAssertEqual(parts.0 + parts.1, 10_000)
        let (left, right) = TripEdits.split(trip, fraction: 0.25, rightPurpose: "Second stop", rightCategory: .business, expenseIDsOnRight: [], now: date(2026, 7, 2, 16))
        XCTAssertEqual(left.milesThousandths + right.milesThousandths, 10_000)
        XCTAssertEqual(left.source, .split)
        XCTAssertTrue(left.isEdited)
        XCTAssertEqual(right.purpose, "Second stop")
        let merged = TripEdits.merge(left, right, purpose: "Both stops", category: .business, now: date(2026, 7, 2, 17))
        XCTAssertEqual(merged.milesThousandths, 10_000)
        XCTAssertEqual(merged.source, .merge)
        XCTAssertTrue(merged.isEdited)
    }

    func testEditingMilesMarksTheSessionTrip() {
        let points = [sample(latitude: 0, time: 0), sample(latitude: 0.001, time: 10)]
        let acceptance = TrackMath.accept(points)
        var draft = TripDraft.session(vehicleId: UUID(), startedAt: date(2026, 7, 4), endedAt: date(2026, 7, 4, 13), acceptance: acceptance)
        XCTAssertFalse(draft.isEdited)
        draft.setMiles(draft.milesThousandths + 500)
        XCTAssertTrue(draft.isEdited)
        XCTAssertTrue(draft.mileageOverridden)
        draft.usePathMileage()
        XCTAssertFalse(draft.mileageOverridden)
        XCTAssertFalse(draft.isEdited)
    }

    func testPinMoveDoesNotChangeMiles() {
        let points = [sample(latitude: 0, time: 0), sample(latitude: 0.001, time: 10)]
        let acceptance = TrackMath.accept(points)
        var draft = TripDraft.session(vehicleId: UUID(), startedAt: date(2026, 7, 4), endedAt: date(2026, 7, 4, 13), acceptance: acceptance)
        let miles = draft.milesThousandths
        draft.placeEnd(Coordinate(latitude: 1, longitude: 1))
        XCTAssertEqual(draft.milesThousandths, miles)
        XCTAssertTrue(draft.isEdited)
    }

    func testExportGateAndCSV() throws {
        var business = makeTrip(start: date(2026, 7, 8), end: date(2026, 7, 8, 15), miles: 2_000)
        business.purpose = ""
        let check = LedgerMath.check(drafts: [business], records: sampleRates(), range: .year(2026), isPlus: false)
        XCTAssertTrue(check.needsPlus)
        XCTAssertEqual(check.missingPurpose, [business.id])
        let recent = LedgerMath.check(drafts: [business], records: sampleRates(), range: .last30Days, isPlus: false)
        XCTAssertFalse(recent.needsPlus)
        business.purpose = "=1+1"
        business.isEdited = true
        let csv = CSVExporter.make(drafts: [business], records: sampleRates(), vehicles: [business.vehicleId: "Civic"])
        for header in ["Date", "From", "To", "Miles", "Category", "Purpose", "Rate cents per mile", "Estimated deduction USD", "Edited"] {
            XCTAssertTrue(csv.contains(header), header)
        }
        XCTAssertTrue(csv.contains("\"'=1+1\""))
        XCTAssertTrue(csv.contains("yes"))
        let pdf = PDFExporter.make(drafts: [business], records: sampleRates(), vehicles: [:], heading: "Mileage log 2026", subtitle: "All vehicles")
        let text = PDFDocument(data: pdf)?.string ?? ""
        XCTAssertTrue(text.contains(Copy.notTaxAdvice))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("certified"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("guaranteed"))
    }

    func testQuotaCountsTheTripMonth() {
        let november = date(2026, 11, 10)
        let dates = (0..<15).map { _ in november } + [date(2026, 10, 2)]
        XCTAssertEqual(Quota.count(startDates: dates, now: november), 15)
        XCTAssertEqual(Quota.monthlyFreeTrips, 15)
    }

    func testLocationCopyMatchesTheSystemPrompt() {
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") as? String,
            Copy.locationUsage
        )
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String,
            Copy.cameraUsage
        )
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        XCTAssertNil(modes)
    }

    private func sampleRates() -> [RateRecord] {
        [
            RateRecord(id: UUID(), category: .business, startDay: "2026-01-01", endDay: "2026-06-30", centsTenths: 725, source: "IRS", notice: "IR-2025-128", createdAt: .distantPast),
            RateRecord(id: UUID(), category: .business, startDay: "2026-07-01", endDay: "2026-12-31", centsTenths: 760, source: "IRS", notice: "IR-2026-29", createdAt: .distantPast)
        ]
    }

    private func makeTrip(start: Date, end: Date, miles: Int, category: TripCategory = .business) -> TripDraft {
        TripDraft(
            id: UUID(),
            vehicleId: UUID(),
            startedAt: start,
            endedAt: end,
            startAddress: "Home",
            endAddress: "Client",
            startCoordinate: nil,
            endCoordinate: nil,
            track: [],
            trimStart: 0,
            trimEnd: 0,
            milesThousandths: miles,
            trackedMilesThousandths: miles,
            mileageOverridden: false,
            placesEdited: false,
            origin: nil,
            category: category,
            purpose: "Client visit",
            notes: "",
            source: .manual,
            expenses: [],
            revisions: [],
            isEdited: false
        )
    }

    private func sample(latitude: Double, time: TimeInterval) -> TrackSample {
        TrackSample(
            id: UUID(),
            latitude: latitude,
            longitude: 0,
            timestamp: Date(timeIntervalSince1970: time),
            horizontalAccuracy: 5,
            segment: 0
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = hour
        parts.timeZone = .current
        return Calendar(identifier: .gregorian).date(from: parts)!
    }
}
