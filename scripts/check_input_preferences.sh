#!/bin/sh
set -eu

missing=0

require_in_file() {
	pattern="$1"
	file="$2"
	if ! /usr/bin/grep -Fq "$pattern" "$file"; then
		echo "Missing '$pattern' in $file"
		missing=1
	fi
}

forbid_in_file() {
	pattern="$1"
	file="$2"
	if /usr/bin/grep -Fq "$pattern" "$file"; then
		echo "Unexpected '$pattern' in $file"
		missing=1
	fi
}

require_in_file "enum DirectDragMode" "OpenParsec/ParsecSDKBridge.swift"
require_in_file "enum ShortcutModifier" "OpenParsec/ParsecSDKBridge.swift"
require_in_file "@AppStorage(\"directDragMode\") public static var directDragMode: DirectDragMode = .scroll" "OpenParsec/SettingsHandler.swift"
require_in_file "@AppStorage(\"shortcutModifier\") public static var shortcutModifier: ShortcutModifier = .control" "OpenParsec/SettingsHandler.swift"
require_in_file "CatItem(\"Direct Drag\")" "OpenParsec/SettingsView.swift"
require_in_file "CatItem(\"Shortcut Modifier\")" "OpenParsec/SettingsView.swift"
require_in_file "handleDirectPanAsScroll" "OpenParsec/ParsecViewController.swift"
require_in_file "let directScrollDivisor: Float = 0.5" "OpenParsec/ParsecViewController.swift"
require_in_file "directLongPressActive" "OpenParsec/ParsecViewController.swift"
require_in_file "directLongPressStartPoint" "OpenParsec/ParsecViewController.swift"
require_in_file "directLongPressDidMove" "OpenParsec/ParsecViewController.swift"
require_in_file "handleDirectLongPressRightClick" "OpenParsec/ParsecViewController.swift"
require_in_file "sendKeyboardShortcut" "OpenParsec/ParsecSDKBridge.swift"
require_in_file "SettingsHandler.shortcutModifier" "OpenParsec/ParsecView.swift"
require_in_file "sendCopyShortcut" "OpenParsec/ParsecView.swift"
require_in_file "sendPasteShortcut" "OpenParsec/ParsecView.swift"
require_in_file "showDirectTouchIndicator" "OpenParsec/ParsecViewController.swift"
require_in_file "hideDirectTouchIndicator" "OpenParsec/ParsecViewController.swift"
require_in_file "makeDirectTouchIndicatorImage" "OpenParsec/ParsecViewController.swift"
require_in_file "UIColor.white.withAlphaComponent(0.55).setFill()" "OpenParsec/ParsecViewController.swift"
require_in_file "\"Direct Drag\"" "OpenParsec/zh-Hans.lproj/Localizable.strings"
require_in_file "\"Shortcut Modifier\"" "OpenParsec/zh-Hans.lproj/Localizable.strings"
require_in_file "\"Copy\"" "OpenParsec/zh-Hans.lproj/Localizable.strings"
require_in_file "\"Paste\"" "OpenParsec/zh-Hans.lproj/Localizable.strings"

forbid_in_file "autoShowKeyboardOnTap" "OpenParsec/SettingsHandler.swift"
forbid_in_file "autoShowKeyboardOnTap" "OpenParsec/SettingsView.swift"
forbid_in_file "showKeyboardIfEnabledAfterTap" "OpenParsec/ParsecViewController.swift"
forbid_in_file "\"Auto Show Keyboard\"" "OpenParsec/zh-Hans.lproj/Localizable.strings"
forbid_in_file "DataManager.model.hostMacOS" "OpenParsec/ParsecSDKBridge.swift"
forbid_in_file "shortcutModifierForHost" "OpenParsec/Shared.swift"

if [ "$missing" -ne 0 ]; then
	exit 1
fi

echo "Input preference implementation contains required hooks."
