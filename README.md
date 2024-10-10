# <p align="center">![icon_transparent.png](OpenParsec/Assets.xcassets/IconTransparent.imageset/icon_transparent.png) ![OpenParsec](OpenParsec/Assets.xcassets/LogoShadow.imageset/logo_shadow.png)</p>

OpenParsec is a simple, open-source Parsec client for iOS/iPadOS written in Swift using the SwiftUI framework and the Parsec SDK.

This project is still a major WIP, so apologies for the currently lackluster documentation. I'm also very new to both Swift and SwiftUI so I'm sure there are many places for improvement.

Before building, make sure you have the Parsec SDK framework symlinked or copied to the `Frameworks` folder. Builds were tested on Xcode Version 12.5.

## On-Screen Keyboard
When streaming, you can tap with 3 fingers to bring up on-screen keyboard.

## Lag / Low Bitrate Issue
If you encounter lags from nowhere or your bitrate hardly goes over 10 Mbps, download Steam Link and do a network test. If you see constant lag spike in the graph, then it's a problem with Apple and there's little we can do to solve this problem. See [here](https://github.com/moonlight-stream/moonlight-ios/issues/627) for more disscussion. 

If you can't change your wireless router's channel to 149 like me, my personal experience is that you can try to power off the device you are using to streaming as well as any nearby Apple devices, especially Mac, then only power on the device you are using to streaming and do the aforementioned network test again. You can turn on other devices if the lag spike is gone and it may sustain for couple hours or days.