import Foundation
import XCTest
@testable import KaosCal

private struct ManualEventKitQACalendar: Codable {
    let title: String
    let accountType: String
    let isWritable: Bool
}

private struct ManualEventKitQAStep: Codable {
    let name: String
    let status: String
    let detail: String
}

private struct ManualEventKitQAReport: Codable {
    let runID: String
    let mode: String
    let startedAt: Date
    var finishedAt: Date?
    let sourceCalendarName: String
    let destinationCalendarName: String
    var authorization: String
    var sourceMatches: [ManualEventKitQACalendar]
    var destinationMatches: [ManualEventKitQACalendar]
    var steps: [ManualEventKitQAStep]
    var success: Bool
}

@MainActor
final class ManualEventKitQATests: XCTestCase {
    func testManualExchangeGate() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["KAOSCAL_EVENTKIT_QA_MODE"] == "inspect" else {
            throw XCTSkip(
                "Manual EventKit QA is read-only and opt-in. "
                    + "Set KAOSCAL_EVENTKIT_QA_MODE=inspect (writes disabled)."
            )
        }
        let mode = "inspect"
        guard let sourceName = environment["KAOSCAL_EVENTKIT_SOURCE"],
              !sourceName.isEmpty,
              let destinationName = environment[
                "KAOSCAL_EVENTKIT_DESTINATION"
              ],
              !destinationName.isEmpty else {
            throw XCTSkip(
                "Manual EventKit QA requires explicit source and destination names."
            )
        }

        let runID = environment["KAOSCAL_EVENTKIT_QA_RUN_ID"]
            ?? Self.makeRunID()
        let outputURL = URL(fileURLWithPath:
            environment["KAOSCAL_EVENTKIT_QA_OUTPUT"]
                ?? NSTemporaryDirectory()
                    .appending("KaosCal-EventKit-QA-\(runID).json")
        )
        let startedAt = Date()
        var report = ManualEventKitQAReport(
            runID: runID,
            mode: mode,
            startedAt: startedAt,
            finishedAt: nil,
            sourceCalendarName: sourceName,
            destinationCalendarName: destinationName,
            authorization: "unknown",
            sourceMatches: [],
            destinationMatches: [],
            steps: [],
            success: false
        )

        let provider = EventKitProvider()
        report.authorization = provider.authorizationState.qaName
        report.steps.append(ManualEventKitQAStep(
            name: "full-access",
            status: provider.authorizationState == .fullAccess
                ? "pass"
                : "blocked",
            detail: provider.authorizationState.title
        ))

        do {
            let calendars = try provider.listCalendars()
            let sourceMatches = calendars.filter { $0.title == sourceName }
            let destinationMatches = calendars.filter {
                $0.title == destinationName
            }
            report.sourceMatches = sourceMatches.map(
                ManualEventKitQACalendar.init
            )
            report.destinationMatches = destinationMatches.map(
                ManualEventKitQACalendar.init
            )

            let source = Self.uniqueWritableExchange(
                sourceMatches
            )
            let destination = Self.uniqueWritableExchange(
                destinationMatches
            )
            report.steps.append(Self.calendarStep(
                name: "source-calendar",
                matches: report.sourceMatches,
                selected: source
            ))
            report.steps.append(Self.calendarStep(
                name: "destination-calendar",
                matches: report.destinationMatches,
                selected: destination
            ))
            let distinct: Bool
            if let source, let destination {
                distinct = source.id != destination.id
            } else {
                distinct = false
            }
            report.steps.append(ManualEventKitQAStep(
                name: "distinct-calendars",
                status: distinct ? "pass" : "blocked",
                detail: distinct
                    ? "Source and destination identifiers differ."
                    : "Source and destination must be different calendars."
            ))

            let preflightPassed = provider.authorizationState == .fullAccess
                && source != nil
                && destination != nil
                && distinct
            report.success = preflightPassed
        } catch {
            report.steps.append(ManualEventKitQAStep(
                name: "calendar-list",
                status: "fail",
                detail: error.localizedDescription
            ))
        }

        report.finishedAt = Date()
        try Self.write(report, to: outputURL)
        print("KAOSCAL_EVENTKIT_QA_REPORT=\(outputURL.path)")

        XCTAssertTrue(
            report.success,
            "Manual EventKit preflight did not pass. Report: \(outputURL.path)"
        )
    }

    private static func uniqueWritableExchange(
        _ matches: [CalendarSource]
    ) -> CalendarSource? {
        guard matches.count == 1,
              let only = matches.first,
              only.isWritable,
              only.accountType == .exchange else {
            return nil
        }
        return only
    }

    private static func calendarStep(
        name: String,
        matches: [ManualEventKitQACalendar],
        selected: CalendarSource?
    ) -> ManualEventKitQAStep {
        if let selected {
            return ManualEventKitQAStep(
                name: name,
                status: "pass",
                detail: "\(selected.title) · Exchange · writable"
            )
        }
        return ManualEventKitQAStep(
            name: name,
            status: "blocked",
            detail: "Expected exactly one Exchange+writable match; found \(matches.count)."
        )
    }

    private static func write(
        _ report: ManualEventKitQAReport,
        to url: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: url, options: .atomic)
    }

    private static func makeRunID() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(8))"
    }
}

private extension ManualEventKitQACalendar {
    init(_ calendar: CalendarSource) {
        self.init(
            title: calendar.title,
            accountType: calendar.accountType.rawValue,
            isWritable: calendar.isWritable
        )
    }
}

private extension CalendarAuthorizationState {
    var qaName: String {
        switch self {
        case .notDetermined: "notDetermined"
        case .fullAccess: "fullAccess"
        case .denied: "denied"
        case .restricted: "restricted"
        case .writeOnly: "writeOnly"
        case .unknown: "unknown"
        }
    }
}
