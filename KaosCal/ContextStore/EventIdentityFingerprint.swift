import CryptoKit
import Foundation

enum EventIdentityFingerprint {
    static func make(event: DisplayEvent) -> String {
        let timeKeys: (String, String)
        let semanticKey: String

        switch event.timeSemantics {
        case let .allDay(start, endExclusive):
            semanticKey = "all_day"
            timeKeys = (localKey(start), localKey(endExclusive))
        case let .floating(start, end):
            semanticKey = "floating"
            timeKeys = (localKey(start), localKey(end))
        case .zoned:
            semanticKey = "zoned"
            timeKeys = (
                instantKey(event.startDate),
                instantKey(event.endDate)
            )
        }

        return digest(fields: [
            normalize(event.calendarIdentifier),
            normalize(event.title),
            normalize(event.location ?? ""),
            semanticKey,
            timeKeys.0,
            timeKeys.1
        ])
    }

    static func makeSeries(event: DisplayEvent) -> String? {
        guard event.isRecurring else { return nil }
        guard let seriesIdentifier = firstNonEmpty(
            event.calendarItemExternalIdentifier,
            event.calendarItemIdentifier
        ) else { return nil }
        return digest(fields: [
            "series",
            normalize(event.calendarIdentifier),
            normalize(seriesIdentifier)
        ])
    }

    static func normalize(_ value: String) -> String {
        value
            .folding(
                options: [
                    .caseInsensitive,
                    .diacriticInsensitive,
                    .widthInsensitive
                ],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    static func firstNonEmpty(_ values: String?...) -> String? {
        values.compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.first
    }

    private static func localKey(
        _ components: LocalDateTimeComponents
    ) -> String {
        [
            String(describing: components.calendarIdentifier),
            String(format: "%04d", components.year),
            String(format: "%02d", components.month),
            String(format: "%02d", components.day),
            String(format: "%02d", components.hour),
            String(format: "%02d", components.minute),
            String(format: "%02d", components.second)
        ].joined(separator: ":")
    }

    private static func instantKey(_ date: Date) -> String {
        String(Int64((date.timeIntervalSince1970 * 1_000).rounded()))
    }

    private static func digest(fields: [String]) -> String {
        let canonical = fields.map {
            "\($0.utf8.count):\($0)"
        }.joined(separator: "|")
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return "v1:" + digest.map { String(format: "%02x", $0) }.joined()
    }
}
