import SwiftUI

/**
 * Category Title
 *
 * Displays a title before the start of a list.
 */
struct CatTitle:View
{
	var text:String
	
	init(_ text:String)
	{
		self.text = text
	}

	var body:some View
	{
		HStack()
		{
			Text(text)
			Spacer()
		}
		.padding(.horizontal)
		.padding(.vertical, 4)
	}
}

/**
 * Category List
 *
 * Displays a list of items. Acts as a container.
 * Use of `CatItem`s is recommended.
 */
struct CatList<Content:View>:View
{
	var content:() -> Content
	
	init(@ViewBuilder content:@escaping () -> Content)
	{
		self.content = content
	}
	
	var body:some View
	{
		VStack(content:content)
			.padding(.vertical, 10)
			.background(Rectangle().fill(Color("BackgroundTab")).cornerRadius(10))
			.padding(.horizontal)
	}
}

/**
 * Category Item
 *
 * Displays a new item with a label in a list.
 * Should be used within `CatList`s.
 */
struct CatItem<Content:View>:View
{
	var title:String
	var content:() -> Content
	
	init(_ title:String, @ViewBuilder content:@escaping () -> Content)
	{
		self.title = title
		self.content = content
	}
	
	var body:some View
	{
		HStack()
		{
			Text(title)
				.lineLimit(1)
			Spacer()
			content()
		}
		.padding(.horizontal)
	}
}

/**
 * Choice
 *
 * Used to depict a single choice with a given label and value.
 */
struct Choice<Enum:Hashable>
{
	var label:String
	var value:Enum
	
	init(_ label:String, _ value:Enum)
	{
		self.label = label;
		self.value = value;
	}
}

/**
 * Segmented Picker
 *
 * Displays a segmented picker with a given list of choices.
 */
struct SegmentPicker<SelectionValue:Hashable>:View
{
	var selection:Binding<SelectionValue>
	var options:[Choice<SelectionValue>]
	
	init(selection:Binding<SelectionValue>, options:[Choice<SelectionValue>])
	{
		self.selection = selection
		self.options = options
	}
	
	var body:some View
	{
		Picker("", selection:selection)
		{
			ForEach(options.indices, id:\.self)
			{ i in
				Text(options[i].label).tag(options[i].value)
			}
		}
		.pickerStyle(.segmented)
	}
}

/**
 * Multiple Choice Picker
 *
 * Displays a button that opens a menu to pick from a given list of choices.
 */
struct MultiPicker<SelectionValue:Hashable>:View
{
	var selection:Binding<SelectionValue>
	var options:[Choice<SelectionValue>]
	
	@State var showChoices:Bool = false
	@State var valueText:String = "Choose..."
	
	init(selection:Binding<SelectionValue>, options:[Choice<SelectionValue>])
	{
		self.selection = selection
		self.options = options
	}
	
	var body:some View
	{
		if #available(iOS 15, *)
		{
			Picker("", selection:selection)
			{
				ForEach(options.indices, id:\.self)
				{ i in
					Text(options[i].label).tag(options[i].value)
				}
			}
			.pickerStyle(.menu)
		}
		else
		{
			// Dumb workaround for older iOS versions. -Angel
			Button(action:{showChoices.toggle()})
			{
				HStack()
				{
					Text(valueText)
						.multilineTextAlignment(.center)
						.padding(.trailing, -4)
					Image(systemName:"chevron.up.chevron.down")
						.font(.system(size:12))
				}
				.foregroundColor(Color("AccentColor"))
			}
			.actionSheet(isPresented:$showChoices)
			{
				genActionSheet()
			}
			.onAppear
			{
				for option in options
				{
					if option.value == selection.wrappedValue
					{
						valueText = option.label
						break
					}
				}
			}
		}
	}
	
	func genActionSheet() -> ActionSheet
	{
		let buttons = options.enumerated().map
		{ i, option in
			Alert.Button.default(Text(option.value == selection.wrappedValue ? "    \(option.label)  ✓" : option.label), action:{select(option)})
		}
		return ActionSheet(title:Text("Pick your preference:"), buttons:buttons + [Alert.Button.cancel()])
	}
	
	func select(_ option:Choice<SelectionValue>)
	{
		valueText = option.label
		selection.wrappedValue = option.value
	}
}

struct ExUI_Previews:PreviewProvider
{
	@State static var value1 = false
	@State static var value2 = true
	
	static var previews:some View
	{
		VStack()
		{
			CatTitle("Category Title")
			CatList()
			{
				CatItem("Category Item")
				{
					Toggle("", isOn:.constant(true))
						.frame(width:80)
				}
			}
			CatTitle("Other Controls")
			CatList()
			{
				CatItem("Segmented Picker")
				{
					SegmentPicker(selection:$value1, options:
					[
						Choice("False", false),
						Choice("True", true)
					])
					.frame(width:180)
				}
				CatItem("Multiple Choice Picker")
				{
					MultiPicker(selection:$value2, options:
					[
						Choice("False", false),
						Choice("True", true)
					])
				}
			}
			Spacer()
		}
		.background(Rectangle().fill(Color("BackgroundGray")).edgesIgnoringSafeArea(.all))
		.foregroundColor(Color("Foreground"))
		.colorScheme(appScheme)
	}
}
