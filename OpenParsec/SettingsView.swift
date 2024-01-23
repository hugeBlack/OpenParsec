import SwiftUI

struct SettingsView:View
{
	@Binding var visible:Bool

	//@State var renderer:RendererType = SettingsHandler.renderer
	@State var decoder:DecoderPref = SettingsHandler.decoder
	//@State var cursorMode:CursorMode = SettingsHandler.cursorMode
	//@State var cursorScale:Float = SettingsHandler.cursorScale
	@State var noOverlay:Bool = SettingsHandler.noOverlay

	var body:some View
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
								Button(action:saveAndExit, label:{ Image(systemName:"xmark").scaleEffect(x:-1) })
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
                        /*CatTitle("Interactivity")
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
                            CatItem("Cursor Scale")
                            {
                                Slider(value: $cursorScale, in:0.1...4, step:0.1)
                            }
                        }*/
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
                            CatItem("Decoder")
                            {
								MultiPicker(selection:$decoder, options:
								[
									Choice("H.264", DecoderPref.h264),
									Choice("Prefer H.265", DecoderPref.h265)
								])
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
                        }
						Text("More options coming soon.")
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
		.scaleEffect(visible ? 1 : 0, anchor:.zero)
		.animation(.easeInOut(duration:0.24))
	}
	
	func saveAndExit()
	{
		//SettingsHandler.renderer = renderer
		SettingsHandler.decoder = decoder
		//SettingsHandler.cursorMode = cursorMode
		//SettingsHandler.cursorScale = cursorScale
		SettingsHandler.noOverlay = noOverlay
		
		SettingsHandler.save()
		
		visible = false
	}
}

struct SettingsView_Previews:PreviewProvider
{
	@State static var value:Bool = true

	static var previews:some View
	{
		SettingsView(visible:$value)
	}
}
