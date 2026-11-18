// Run: swiftc OpenParsec/KoreanKeyboardRouter.swift Tests/main.swift -o /tmp/keyboard-tests && /tmp/keyboard-tests
typealias Event = KoreanKeyboardRouter.Event
func down(_ code: Int) -> Event { Event(code: code, pressed: true) }
func up(_ code: Int) -> Event { Event(code: code, pressed: false) }
let toggle = [down(230), up(230)]
var router = KoreanKeyboardRouter()

for key in [144, 230] {
    assert(router.handle(code: key, pressed: true) == toggle)
    assert(router.handle(code: key, pressed: true).isEmpty)
    assert(router.repeatKey == nil)
    assert(router.handle(code: key, pressed: false).isEmpty)
}
for modifier in [224, 225, 228, 229] {
    assert(router.handle(code: modifier, pressed: true) == [down(modifier)])
    assert(router.handle(code: 44, pressed: true) == [up(modifier)] + toggle)
    assert(router.repeatKey == nil)
    assert(router.handle(code: 44, pressed: true).isEmpty)
    // Type before the keyboard delivers its delayed modifier-up: no Ctrl/Shift.
    assert(router.handle(code: 4, pressed: true) == [down(4)])
    assert(router.handle(code: 4, pressed: false) == [up(4)])
    assert(router.handle(code: modifier, pressed: false).isEmpty)
    assert(router.handle(code: 44, pressed: false).isEmpty)
    // An explicit new modifier press must still work normally.
    assert(router.handle(code: modifier, pressed: true) == [down(modifier)])
    assert(router.handle(code: modifier, pressed: false) == [up(modifier)])
}
// Reverse release order and repeats during the delayed Ctrl-up window.
_ = router.handle(code: 224, pressed: true)
assert(router.handle(code: 44, pressed: true) == [up(224)] + toggle)
assert(router.handle(code: 44, pressed: false).isEmpty)
assert(router.handle(code: 224, pressed: true).isEmpty)
assert(router.handle(code: 44, pressed: true) == [down(44)])
assert(router.handle(code: 44, pressed: false) == [up(44)])
assert(router.reset().isEmpty)
assert(router.handle(code: 224, pressed: false).isEmpty)
// A dedicated language key also releases a companion Ctrl immediately.
for key in [144, 230, 53] {
    _ = router.handle(code: 224, pressed: true)
    assert(router.handle(code: key, pressed: true, mapBacktick: true) == [up(224)] + toggle)
    assert(router.reset().isEmpty)
}
// Ordinary typing, shortcuts, and real backtick stay intact.
assert(router.handle(code: 53, pressed: true) == [down(53)])
assert(router.repeatKey == 53)
assert(router.handle(code: 53, pressed: false) == [up(53)])
assert(router.handle(code: 53, pressed: true, mapBacktick: true) == toggle)
assert(router.handle(code: 53, pressed: false).isEmpty)
assert(router.handle(code: 227, pressed: true) == [down(227)])
assert(router.handle(code: 44, pressed: true) == [down(44)])
assert(router.reset() == [up(44), up(227)])
// Ctrl+Shift+Space is not one of our language shortcuts.
_ = router.handle(code: 224, pressed: true)
_ = router.handle(code: 225, pressed: true)
assert(router.handle(code: 44, pressed: true) == [down(44)])
_ = router.reset()
// UIKit fallback may report modifier flags without a modifier press.
assert(router.handle(code: 44, pressed: true, spaceShortcut: true) == toggle)
assert(router.handle(code: 44, pressed: false).isEmpty)
// UIKit flags must not resurrect a consumed Ctrl/Shift while key-up is delayed.
for modifier in [224, 225, 228, 229] {
    assert(router.handle(code: modifier, pressed: true) == [down(modifier)])
    assert(router.handle(code: 44, pressed: true, spaceShortcut: true) == [up(modifier)] + toggle)
    assert(router.handle(code: 44, pressed: false).isEmpty)
    assert(router.handle(code: 44, pressed: true, spaceShortcut: true) == [down(44)])
    assert(router.handle(code: 44, pressed: false) == [up(44)])
    assert(router.handle(code: modifier, pressed: false).isEmpty)
    // After release, a later flags-only shortcut remains supported.
    assert(router.handle(code: 44, pressed: true, spaceShortcut: true) == toggle)
    assert(router.handle(code: 44, pressed: false).isEmpty)
}
// An incomplete flag snapshot must not override a known multi-modifier chord.
_ = router.handle(code: 224, pressed: true)
_ = router.handle(code: 225, pressed: true)
assert(router.handle(code: 44, pressed: true, spaceShortcut: true) == [down(44)])
assert(router.reset() == [up(44), up(224), up(225)])
// Cancellation/disconnection clears consumed keys as well as forwarded keys.
_ = router.handle(code: 144, pressed: true)
_ = router.handle(code: 4, pressed: true)
assert(router.reset() == [up(4)])
assert(router.repeatKey == nil)
assert(router.handle(code: 4, pressed: false).isEmpty)
assert(router.handle(code: 144, pressed: true) == toggle)
_ = router.reset()
// A touch toggle also preserves held modifiers and stops key repeat.
_ = router.handle(code: 225, pressed: true)
_ = router.handle(code: 4, pressed: true)
assert(router.toggle() == [up(225)] + toggle + [down(225)])
assert(router.repeatKey == nil)
assert(router.handle(code: 4, pressed: false) == [up(4)])
assert(router.handle(code: 225, pressed: false) == [up(225)])
assert(router.handle(code: 0, pressed: true).isEmpty)

print("Korean keyboard event-sequence tests passed")
