// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import ATCCore

/// Fixtures: `supervisor-alerts.json` and `alert-event-initial.json` come from a real
/// read of atc on 2026-09-29 (subset, paths scrubbed). `supervisor-summary-v1.json` is
/// hand-written from docs/mac-app.md; `supervisor-summary-live.json` is a real read of ATC-153 (scrubbed).
enum Fixtures {
    static func data(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }
}

func alert(_ key: String, _ level: AlertLevel?, cue: AlertCue? = nil) -> SupervisorAlert {
    SupervisorAlert(key: key, group: "alert", level: level, cue: cue, text: key)
}
