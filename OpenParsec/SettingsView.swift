import SwiftUI

struct SettingsView:View
{
	@Binding var visible: Bool

	//@State var renderer:RendererType = SettingsHandler.renderer
	@AppStorage("resolution") var resolution: ParsecResolution = .client
	@AppStorage("bitrate") var bitrate: Int = 0
	@AppStorage("decoder") var decoder: DecoderPref = .h264
	@AppStorage("cursorMode") var cursorMode: CursorMode = .touchpad
	@AppStorage("cursorScale") var cursorScale: Double = 0.5
	@AppStorage("mouseSensitivity") var mouseSensitivity: Double = 1.0
	@AppStorage("noOverlay") var noOverlay: Bool = false
	@AppStorage("cursorScale") var hideStatusBar: Bool = true
	@AppStorage("rightClickPosition") var rightClickPosition: RightClickPosition = .firstFinger
	@AppStorage("preferredFramesPerSecond") var preferredFramesPerSecond: Int = 60 // 0 = use device max (ProMotion)
	@AppStorage("decoderCompatibility") var decoderCompatibility: Bool = false // Enable for stutter issues on some devices
	@AppStorage("showKeyboardButton") var showKeyboardButton: Bool = true
	@AppStorage("syncKeyboardLayout") var syncKeyboardLayout: Bool = true
	@AppStorage("layoutSyncHotkey") var layoutSyncHotkey: LayoutSyncHotkey = .ctrlSpace
	@AppStorage("saveSessionSettings") var saveSessionSettings: Bool = true
	
	let resolutionChoices: [Choice<ParsecResolution>]

	init(visible: Binding<Bool>) {
		_visible = visible
		var tmp: [Choice<ParsecResolution>] = []
		for res in ParsecResolution.resolutions {
			tmp.append(Choice(res.desc, res))
		}
		resolutionChoices = tmp
	}
	
	var body: some View
	{
		ZStack()
		{
			if (visible)
			{
				// Background
				Rectangle()
					.fill(Color.init(red:0, green:0, blue:0, opacity:0.67))
					.edgesIgnoringSafeArea(.all)
			}
		}
		.animation(.linear(duration:0.24))

		ZStack()
		{
			if (visible)
			{
				// Main controls
				VStack()
				{
					// Navigation controls
					ZStack()
					{
						Rectangle()
							.fill(Color("BackgroundTab"))
							.frame(height:52)
							.shadow(color:Color("Shading"), radius:4, y:6)
						ZStack()
						{
							HStack()
							{
								Button(action: saveAndExit, label:{ Image(systemName:"xmark").scaleEffect(x:-1) })
								 .padding()
								Spacer()
							}
							Text("Settings")
								.multilineTextAlignment(.center)
								.foregroundColor(Color("Foreground"))
								.font(.system(size:20, weight:.medium))
							Spacer()
						}
						.foregroundColor(Color("AccentColor"))
					}
					.zIndex(1)

					ScrollView()
					{
                        CatTitle("Interactivity")
                        CatList()
                        {
                            CatItem("Mouse Movement")
                            {
                                MultiPicker(selection:$cursorMode, options:
								[
									Choice("Touchpad", CursorMode.touchpad),
									Choice("Direct", CursorMode.direct)
								])
                            }
							CatItem("Right Click Position")
							{
								MultiPicker(selection:$rightClickPosition, options:
								[
									Choice("First Finger", RightClickPosition.firstFinger),
									Choice("Middle", RightClickPosition.middle),
									Choice("Second Finger", RightClickPosition.secondFinger)
								])
							}
                            CatItem("Cursor Scale")
                            {
                                Slider(value: $cursorScale, in:0.1...4, step:0.1)
									.frame(width: 200)
								Text(String(format: "%.1f", cursorScale))
                            }
							CatItem("Mouse Sensitivity")
							{
								Slider(value: $mouseSensitivity, in:0.1...4, step:0.1)
									.frame(width: 200)
								Text(String(format: "%.1f", mouseSensitivity))
							}
                        }
                        CatTitle("Keyboard")
                        CatList()
                        {
                            CatItem("Sync layout with host")
                            {
                                Toggle("", isOn:$syncKeyboardLayout)
                                    .frame(width:80)
                            }
                            CatItem("Layout switch hotkey")
                            {
                                MultiPicker(selection:$layoutSyncHotkey, options:
                                [
                                    Choice("Off", LayoutSyncHotkey.none),
                                    Choice("Ctrl + Space", LayoutSyncHotkey.ctrlSpace),
                                    Choice("Cmd + Space", LayoutSyncHotkey.cmdSpace),
                                    Choice("Alt + Space", LayoutSyncHotkey.altSpace),
                                    Choice("Alt + Shift", LayoutSyncHotkey.altShift)
                                ])
                            }
                        }
                        CatTitle("Graphics")
                        CatList()
                        {
                            /*CatItem("Renderer")
                            {
								SegmentPicker(selection:$renderer, options:
								[
									Choice("OpenGL", RendererType.opengl),
									Choice("Metal", RendererType.metal)
								])
                                .frame(width:165)
                            }*/
							CatItem("Default Resolution")
							{
								MultiPicker(selection: $resolution, options:resolutionChoices)
							}
                            CatItem("Decoder")
                            {
								MultiPicker(selection: $decoder, options:
								[
									Choice("H.264", DecoderPref.h264),
									Choice("Prefer H.265", DecoderPref.h265)
								])
                            }
							CatItem("Frame Rate")
							{
								MultiPicker(selection: $preferredFramesPerSecond, options:
								[
									Choice("Auto (Device Max)", 0),
									Choice("120 FPS", 120),
									Choice("60 FPS", 60),
									Choice("30 FPS", 30)
								])
							}
							CatItem("Decoder Compatibility")
							{
								Toggle("", isOn:$decoderCompatibility)
									.frame(width:80)
							}
                        }
                        CatTitle("Misc")
                        CatList()
                        {
                            CatItem("Never Show Overlay")
                            {
                                Toggle("", isOn:$noOverlay)
                                    .frame(width:80)
                            }
							CatItem("Hide Status Bar")
							{
								Toggle("", isOn:$hideStatusBar)
									.frame(width:80)
							}
							CatItem("Show Keyboard Button")
							{
								Toggle("", isOn:$showKeyboardButton)
									.frame(width:80)
							}
							CatItem("Save Session Settings")
							{
								Toggle("", isOn:$saveSessionSettings)
									.frame(width:80)
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
				.animation(.none)
			}
		}
        .preferredColorScheme(appScheme)
		.scaleEffect(visible ? 1 : 0, anchor:.zero)
		.animation(.easeInOut(duration:0.24))
	}
	
	func saveAndExit()
	{
		//SettingsHandler.renderer = renderer
		visible = false
	}
	
	func getVersionInfo() -> String {
		return "Version \(Bundle.main.infoDictionary!["CFBundleShortVersionString"] ?? "Unknown versino")-\(Bundle.main.infoDictionary!["GitCommitInfo"] ?? "Unknown commit")"
	}
}

struct SettingsView_Previews:PreviewProvider
{
	@State static var value: Bool = true

	static var previews: some View
	{
		SettingsView(visible:$value)
	}
}
