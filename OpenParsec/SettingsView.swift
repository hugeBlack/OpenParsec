import SwiftUI

struct SettingsView: View {
	@Binding var visible: Bool
	@ObservedObject private var settings = SettingsStore.shared

	init(visible: Binding<Bool>) {
		_visible = visible
	}

	var body: some View {
		NavigationStack {
			Form {
				Section("Touch & Mouse") {
					Picker("Touch Mode", selection: $settings.cursorMode) {
						Text("Touchpad").tag(CursorMode.touchpad)
						Text("Direct").tag(CursorMode.direct)
					}
					Picker("Right Click", selection: $settings.rightClickPosition) {
						Text("First Finger").tag(RightClickPosition.firstFinger)
						Text("Middle").tag(RightClickPosition.middle)
						Text("Second Finger").tag(RightClickPosition.secondFinger)
					}
					Toggle("Cursor momentum", isOn: $settings.cursorMomentum)
					sliderRow("Pointer Speed", value: $settings.mouseSensitivity, range: 0.1...4, step: 0.1)
					sliderRow("Cursor Size", value: $settings.cursorScale, range: 0.1...4, step: 0.1)
					sliderRow("Scroll Speed", value: $settings.scrollSensitivity, range: 0.5...5, step: 0.5)
					Toggle("Reverse Scrolling", isOn: $settings.reverseScrollDirection)
					Toggle("Pinch to Zoom", isOn: $settings.zoomEnabled)
				}

				Section("Keyboard") {
					Toggle("Show Keyboard Button", isOn: $settings.showKeyboardButton)
					Toggle("Option Key as Command", isOn: $settings.optionAsCommand)
				}

				Section("Video") {
					Picker("Renderer", selection: $settings.renderer) {
						Text("OpenGL").tag(RendererType.opengl)
						Text("Metal").tag(RendererType.metal)
					}
					.pickerStyle(.segmented)
					Picker("Resolution", selection: $settings.resolution) {
						ForEach(ParsecResolution.resolutions, id: \.self) { res in
							Text(res.desc).tag(res)
						}
					}
					Picker("Bitrate", selection: $settings.bitrate) {
						Text("Host Default").tag(0)
						ForEach(ParsecResolution.bitrates, id: \.self) { rate in
							Text("\(rate) Mbps").tag(rate)
						}
					}
					Picker("Frame Rate", selection: $settings.preferredFramesPerSecond) {
						Text("Auto (Device Max)").tag(0)
						Text("120 FPS").tag(120)
						Text("60 FPS").tag(60)
						Text("30 FPS").tag(30)
					}
					Toggle("Constant Frame Rate", isOn: $settings.constantFps)
					Picker("Codec", selection: $settings.decoder) {
						Text("H.264").tag(DecoderPref.h264)
						Text("Prefer H.265").tag(DecoderPref.h265)
					}
				}

				Section("During a Stream") {
					Toggle("Show Stream Stats", isOn: $settings.alwaysShowStatus)
					Toggle("Show Menu Button", isOn: Binding(get: { !settings.noOverlay }, set: { settings.noOverlay = !$0 }))
					Picker("Menu Edge Swipe", selection: $settings.menuSwipeEdge) {
						Text("Off").tag(MenuSwipeEdge.off)
						Text("Left Edge").tag(MenuSwipeEdge.left)
						Text("Right Edge").tag(MenuSwipeEdge.right)
					}
					Toggle(UIDevice.current.userInterfaceIdiom == .pad ? "Hide iPad Status Bar" : "Hide iPhone Status Bar", isOn: $settings.hideStatusBar)
					Toggle("Picture in Picture", isOn: $settings.enablePiP)
					Toggle("Start Muted", isOn: $settings.startMuted)
				}

				Section("Developer") {
					Toggle("Auto Reconnect", isOn: $settings.autoReconnect)
					if settings.autoReconnect {
						Toggle("Show Reconnect Errors", isOn: $settings.errorPrompts)
					}
				}

				Section {
					EmptyView()
				} footer: {
					Text(getVersionInfo())
						.frame(maxWidth: .infinity)
				}
			}
			.navigationTitle("Settings")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button("Done") { visible = false }
				}
			}
		}
	}

	private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
		VStack(alignment: .leading) {
			HStack {
				Text(title)
				Spacer()
				Text(String(format: "%.1f", value.wrappedValue))
					.foregroundStyle(.secondary)
					.monospacedDigit()
			}
			Slider(value: value, in: range, step: step)
				.accessibilityLabel(title)
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
