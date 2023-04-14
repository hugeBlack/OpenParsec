import SwiftUI

struct SettingsView:View
{
	@Binding var visible:Bool

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
								Button(action:{ visible = false }, label:{ Image(systemName:"xmark").scaleEffect(x:-1) })
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
						Text("This menu is a work in progress.\nCheck back later.")
							.multilineTextAlignment(.center)
							.foregroundColor(Color("Foreground"))
							.opacity(0.5)
							.padding()
					}
				}
				.background(Rectangle().fill(Color("BackgroundGray")))
				.cornerRadius(8)
				.padding()
			}
		}
		.scaleEffect(visible ? 1 : 0, anchor:.zero)
		.animation(.easeInOut(duration:0.24))
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
