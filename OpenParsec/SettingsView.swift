import SwiftUI

struct SettingsView: View {
	@Binding var visible: Bool
	@ObservedObject private var settings = SettingsStore.shared

	let resolutionChoices: [Choice<ParsecResolution>]

	init(visible: Binding<Bool>) {
		_visible = visible
		var tmp: [Choice<ParsecResolution>] = []
		for res in ParsecResolution.resolutions {
			tmp.append(Choice(res.desc, res))
		}
		resolutionChoices = tmp
	}

	var body: some View {
		ZStack {
			if visible {
				// Background
				Rectangle()
					.fill(Color.init(red: 0, green: 0, blue: 0, opacity: 0.67))
					.edgesIgnoringSafeArea(.all)
			}
		}

		ZStack {
			if visible {
				// Main controls
				VStack {
					// Navigation controls
					ZStack {
						Rectangle()
							.fill(Color("BackgroundTab"))
							.frame(height: 52)
							.shadow(color: Color("Shading"), radius: 4, y: 6)
						ZStack {
							HStack {
								Button(action: saveAndExit, label: { Image(systemName: "xmark").scaleEffect(x: -1) })
								 .padding()
								Spacer()
							}
							Text("Settings")
								.multilineTextAlignment(.center)
								.foregroundColor(Color("Foreground"))
								.font(.system(size: 20, weight: .medium))
							Spacer()
						}
						.foregroundColor(Color("AccentColor"))
					}
					.zIndex(1)

					ScrollView {
						CatTitle("Touch & Mouse")
						CatList {
							CatItem("Touch Mode") {
								MultiPicker(selection: $settings.cursorMode, options:
								[
									Choice("Touchpad", CursorMode.touchpad),
									Choice("Direct", CursorMode.direct)
								])
							}
							CatItem("Right Click") {
								MultiPicker(selection: $settings.rightClickPosition, options:
								[
									Choice("First Finger", RightClickPosition.firstFinger),
									Choice("Middle", RightClickPosition.middle),
									Choice("Second Finger", RightClickPosition.secondFinger)
								])
							}
							CatSlider("Pointer Speed", value: $settings.mouseSensitivity, in: 0.1...4, step: 0.1)
							CatSlider("Cursor Size", value: $settings.cursorScale, in: 0.1...4, step: 0.1)
							CatSlider("Scroll Speed", value: $settings.scrollSensitivity, in: 0.5...5, step: 0.5)
							CatItem("Reverse Scrolling") {
								Toggle("", isOn: $settings.reverseScrollDirection)
									.frame(width: 80)
							}
							CatItem("Pinch to Zoom") {
								Toggle("", isOn: $settings.zoomEnabled)
									.frame(width: 80)
							}
						}
						CatTitle("Keyboard")
						CatList {
							CatItem("Show Keyboard Button") {
								Toggle("", isOn: $settings.showKeyboardButton)
									.frame(width: 80)
							}
							CatItem("Option Key as Command") {
								Toggle("", isOn: $settings.optionAsCommand)
									.frame(width: 80)
							}
						}
						CatTitle("Video")
						CatList {
							CatItem("Renderer") {
								SegmentPicker(selection: $settings.renderer, options: [
									Choice("OpenGL", RendererType.opengl),
									Choice("Metal", RendererType.metal)
								])
								.frame(width: 165)
							}
							CatItem("Resolution") {
								MultiPicker(selection: $settings.resolution, options: resolutionChoices)
							}
							CatItem("Bitrate") {
								MultiPicker(selection: $settings.bitrate, options: [Choice("Host Default", 0)] + ParsecResolution.bitrates.map { Choice("\($0) Mbps", $0) })
							}
							CatItem("Frame Rate") {
								MultiPicker(selection: $settings.preferredFramesPerSecond, options:
								[
									Choice("Auto (Device Max)", 0),
									Choice("120 FPS", 120),
									Choice("60 FPS", 60),
									Choice("30 FPS", 30)
								])
							}
							CatItem("Constant Frame Rate") {
								Toggle("", isOn: $settings.constantFps)
									.frame(width: 80)
							}
							CatItem("Codec") {
								MultiPicker(selection: $settings.decoder, options:
								[
									Choice("H.264", DecoderPref.h264),
									Choice("Prefer H.265", DecoderPref.h265)
								])
							}
						}
						CatTitle("During a Stream")
						CatList {
							CatItem("Show Stream Stats") {
								Toggle("", isOn: $settings.alwaysShowStatus)
									.frame(width: 80)
							}
							CatItem("Show Menu Button") {
								Toggle("", isOn: Binding(get: { !settings.noOverlay }, set: { settings.noOverlay = !$0 }))
									.frame(width: 80)
							}
							CatItem("Menu Edge Swipe") {
								MultiPicker(selection: $settings.menuSwipeEdge, options:
								[
									Choice("Off", MenuSwipeEdge.off),
									Choice("Left Edge", MenuSwipeEdge.left),
									Choice("Right Edge", MenuSwipeEdge.right)
								])
							}
							CatItem("Hide Status Bar") {
								Toggle("", isOn: $settings.hideStatusBar)
									.frame(width: 80)
							}
							CatItem("Picture in Picture") {
								Toggle("", isOn: $settings.enablePiP)
									.frame(width: 80)
							}
							CatItem("Start Muted") {
								Toggle("", isOn: $settings.startMuted)
									.frame(width: 80)
							}
						}
						CatTitle("Developer")
						CatList {
							CatItem("Auto Reconnect") {
								Toggle("", isOn: $settings.autoReconnect)
									.frame(width: 80)
							}
							if settings.autoReconnect {
								CatItem("Show Reconnect Errors") {
									Toggle("", isOn: $settings.errorPrompts)
										.frame(width: 80)
								}
							}
						}
						Text(getVersionInfo())
							.multilineTextAlignment(.center)
							.opacity(0.5)
							.padding()
					}
                    .foregroundColor(Color("Foreground"))
				}
				.background(Rectangle().fill(Color("BackgroundGray")))
				.cornerRadius(8)
				.padding()
			}
		}
        .preferredColorScheme(appScheme)
		.scaleEffect(visible ? 1 : 0, anchor: .zero)
	}

	func saveAndExit() {
		// SettingsHandler.renderer = renderer
		withAnimation(.easeInOut(duration: 0.24)) {
			visible = false
		}
	}

	func getVersionInfo() -> String {
		let info = Bundle.main.infoDictionary
		let version = info?["CFBundleShortVersionString"] as? String ?? "Unknown version"
		let commit = info?["GitCommitInfo"] as? String ?? "Unknown commit"
		return "Version \(version)-\(commit)"
	}
}

struct SettingsView_Previews: PreviewProvider {
	@State static var value: Bool = true

	static var previews: some View {
		SettingsView(visible: $value)
	}
}
