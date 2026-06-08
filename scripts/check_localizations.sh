#!/bin/sh
set -eu

strings_file="OpenParsec/zh-Hans.lproj/Localizable.strings"

if [ ! -f "$strings_file" ]; then
	echo "Missing $strings_file"
	exit 1
fi

missing=0

while IFS= read -r key; do
	[ -n "$key" ] || continue
	if ! /usr/bin/grep -Fq "\"$key\"" "$strings_file"; then
		echo "Missing localization key: $key"
		missing=1
	fi
done <<'KEYS'
Email
Password
Login
Loading...
Please enter your 2FA code from your authenticator app
2FA Code
Cancel
Enter
Login Failed
Are you sure you want to logout?
Logout
Connect
You
Friends
Hosts
%d host
%d hosts
%d friend
%d friends
Last refreshed at %@
Requesting connection to %@...
Refreshing hosts...
Error gathering hosts: Invalid session
Error gathering hosts: %@
Error gathering user info: %@
Error gathering friends: %@
Error connecting to host (code %d)
Error: %@
Settings
Interactivity
Mouse Movement
Touchpad
Direct
Right Click Position
First Finger
Middle
Second Finger
Cursor Scale
Mouse Sensitivity
Graphics
Default Resolution
Host Resolution
Client Resolution
Decoder
Prefer H.265
Frame Rate
Auto (Device Max)
Decoder Compatibility
Misc
Never Show Overlay
Hide Status Bar
Show Keyboard Button
Save Session Settings
Version %@-%@
Unknown versino
Unknown commit
Disconnected (reason unknown)
Disconnected (code %d)
Decode %@ms    Encode %@ms    Network %@ms    Bitrate %@Mbps    %@ %@x%@ %@ %@
Close
Hide Overlay
Sound: %@
OFF
ON
Resolution
Bitrate
Auto
Switch Display
Constant FPS: %@
Zoom: %@
Disconnect
Pick your preference:
Choose...
Done
KEYS

if [ "$missing" -ne 0 ]; then
	exit 1
fi

echo "Localization resources contain required zh-Hans keys."
