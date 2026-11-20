// USB HID usages, matching Parsec's physical key codes. Kept independent of
// UIKit/GameController so event sequences can be tested on the build machine.
struct KoreanKeyboardRouter {
    struct Event: Equatable {
        let code: Int
        let pressed: Bool
    }

    private var held: Set<Int> = []
    private var forwarded: Set<Int> = []
    private var consumed: Set<Int> = []
    private(set) var repeatKey: Int?

    mutating func handle(code: Int, pressed: Bool, mapBacktick: Bool = false,
                         spaceShortcut: Bool = false) -> [Event] {
        guard code > 3 && code < 65535 else { return [] }
        if !pressed {
            held.remove(code)
            if repeatKey == code { repeatKey = nil }
            if consumed.remove(code) != nil { return [] }
            guard forwarded.remove(code) != nil else { return [] }
            return [Event(code: code, pressed: false)]
        }
        // A held language key must toggle once, never at the repeat rate.
        guard held.insert(code).inserted else { return [] }
        let modifiers = held.subtracting(consumed).filter { (224...231).contains($0) }
        let shiftOnly = !modifiers.isEmpty && modifiers.allSatisfy { $0 == 225 || $0 == 229 }
        let controlOnly = !modifiers.isEmpty && modifiers.allSatisfy { $0 == 224 || $0 == 228 }
        // UIKit sometimes supplies only flags, without a modifier key-down.
        // When we do know the physical state, prefer it: a consumed Ctrl/Shift
        // may remain in those flags until its delayed key-up arrives.
        let shortcutFromFlags = spaceShortcut && !held.contains(where: { (224...231).contains($0) })
        let languageKey = code == 144 || code == 230 || (mapBacktick && code == 53)
        if languageKey || (code == 44 && (shortcutFromFlags || shiftOnly || controlOnly)) {
            consumed.insert(code)
            return toggle(consumeModifiers: true)
        }
        forwarded.insert(code)
        // Lock keys and language keys must not acquire the software repeat timer.
        if !(224...231).contains(code) && ![57, 71, 83, 145].contains(code) {
            repeatKey = code
        }
        return [Event(code: code, pressed: true)]
    }

    mutating func toggle(consumeModifiers: Bool = false) -> [Event] {
        repeatKey = nil
        let modifiers = forwarded.filter { (224...231).contains($0) }.sorted()
        if consumeModifiers {
            // Bluetooth language keys can emit Ctrl+Space with a delayed Ctrl-up.
            // End the whole shortcut now; ignore those modifiers until real key-up.
            // Re-pressing Ctrl/Shift starts an ordinary shortcut immediately.
            for code in modifiers {
                forwarded.remove(code)
                consumed.insert(code)
            }
        }
        return modifiers.map { Event(code: $0, pressed: false) }
            + [Event(code: 230, pressed: true), Event(code: 230, pressed: false)]
            + (consumeModifiers ? [] : modifiers.map { Event(code: $0, pressed: true) })
    }

    mutating func reset() -> [Event] {
        let releases = forwarded.sorted().map { Event(code: $0, pressed: false) }
        held.removeAll()
        forwarded.removeAll()
        consumed.removeAll()
        repeatKey = nil
        return releases
    }
}
