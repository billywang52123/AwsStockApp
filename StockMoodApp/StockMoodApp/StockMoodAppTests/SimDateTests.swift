import Foundation
import Testing
@testable import StockMoodApp

@MainActor
struct SimDateTests {
    @Test
    func statusDecodesBackendSchemaWithoutDateTimezoneConversion() throws {
        let json = Data(
            """
            {
              "overridden": true,
              "effective_today": "2026-03-15",
              "simulated_trade_date": "2025-03-15",
              "resolved_data_date": "2025-03-14",
              "data_available": true
            }
            """.utf8
        )
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let status = try decoder.decode(SimDateStatus.self, from: json)

        #expect(status.overridden)
        #expect(status.effectiveToday == "2026-03-15")
        #expect(status.simulatedTradeDate == "2025-03-15")
        #expect(status.resolvedDataDate == "2025-03-14")
        #expect(status.dataAvailable)
    }

    @Test
    func updateBodyEncodesDateOnlyPayload() throws {
        let encoded = try JSONEncoder().encode(SimDateUpdateBody(date: "2026-03-15"))
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: String])

        #expect(object == ["date": "2026-03-15"])
    }
}
