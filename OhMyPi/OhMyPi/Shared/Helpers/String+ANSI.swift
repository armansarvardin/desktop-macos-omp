//
//  String+ANSI.swift
//  OhMyPi
//
//  Created by Arman Sarvardin on 22/9/26.
//

import Foundation

extension String {
    /// Removes terminal escape sequences (colours, cursor moves, OSC titles) from CLI output.
    nonisolated var strippingANSI: String {
        let escape = "\u{1B}"
        let patterns = [
            "\(escape)\\[[0-9;?]*[ -/]*[@-~]",
            "\(escape)\\][^\u{07}]*\u{07}"
        ]

        return patterns.reduce(self) { text, pattern in
            text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
    }
}
