/// Maps macOS virtual key codes to a sound type and a stereo position on the keyboard.
enum KeyMap {
    static let capsLock: Int64 = 57

    static func kind(for code: Int64, isDown: Bool) -> SoundKind {
        guard isDown else { return .up }
        switch code {
        case 49: return .space
        case 36, 76, 56, 60, 57: return .enter      // return, keypad enter, shifts, caps — big stabilized keys
        case 51, 117: return .backspace             // delete, forward delete
        default: return .down
        }
    }

    /// -1 (left) ... 1 (right), based on the MacBook ANSI layout plus full-size extras.
    static func pan(for code: Int64) -> Float {
        positions[code] ?? 0
    }

    private static let rows: [[Int64]] = [
        [50, 18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24, 51],
        [48, 12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30, 42],
        [57, 0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39, 36],
        [56, 6, 7, 8, 9, 11, 45, 46, 43, 47, 44, 60],
        [63, 59, 58, 55, 49, 54, 61, 123, 126, 125, 124],
        [53, 122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111],
    ]

    private static let positions: [Int64: Float] = {
        var map: [Int64: Float] = [:]
        for row in rows {
            for (i, code) in row.enumerated() {
                map[code] = Float(i) / Float(row.count - 1) * 2 - 1
            }
        }
        map[49] = 0 // space bar is centered
        // Full-size external keyboards: navigation cluster and number pad sit on the far right.
        for code: Int64 in [114, 115, 116, 117, 119, 121, 105, 107, 113] { map[code] = 0.85 }
        for code: Int64 in [71, 81, 75, 67, 89, 91, 92, 78, 86, 87, 88, 69, 83, 84, 85, 76, 82, 65] { map[code] = 1 }
        return map
    }()
}
