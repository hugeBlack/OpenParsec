import ParsecSDK
import UIKit

class KeyboardViewController:UIViewController
{
	override func viewDidLoad()
	{
		super.viewDidLoad()
		print("KeyboardViewController did load!")
	}

	@objc func handleKeyCommand(sender:UIKeyCommand)
	{
		print("KeyboardViewController keyboard info: \(sender)")

//		CParsec.sendKeyboardMessage(sender:sender)
	}

	@objc func handleModifierKeyCommand(sender:UIKeyCommand)
	{
		print("KeyboardViewController keyboard modifier info \(sender.modifierFlags.rawValue)")
	}

	override var keyCommands:[UIKeyCommand]?
	{
		// Create an array to hold the key commands
		var commands = [UIKeyCommand]()

		// Add a key command for each printable ASCII character
		for scalar in (Unicode.Scalar(32)...Unicode.Scalar(255)).makeIterator()
		{
			let input = String(scalar)
			let keyCommand = UIKeyCommand(action:#selector(handleKeyCommand(sender:)), input:input, modifierFlags:[], propertyList:input)
			print("Key added to the Commands: \(input)")
			commands.append(keyCommand)
		}

		// ESC Key
		let escKeyCommand = UIKeyCommand(action:#selector(handleKeyCommand(sender:)), input:UIKeyCommand.inputEscape, modifierFlags:[], propertyList:nil)

		// TAB Key
		let tabKeyCommand = UIKeyCommand(action:#selector(handleKeyCommand(sender:)), input:"\t", modifierFlags:[], propertyList:nil)

		// Shift Keys
		let shiftKeyCommand = UIKeyCommand(action:#selector(handleKeyCommand(sender:)), input:"", modifierFlags:.shift, propertyList:nil)

		// CTRL Key
		let ctrlKeyCommand = UIKeyCommand(action:#selector(handleKeyCommand(sender:)), input:"", modifierFlags:.control, propertyList:nil)

		// CMD Key
		let commandKey = UIKeyCommand(action:#selector(handleKeyCommand(sender:)), input:"", modifierFlags:.command, propertyList:nil)

		// Return the array of key commands
		return commands +
		[
			 escKeyCommand,
			 tabKeyCommand,
			 shiftKeyCommand,
			 ctrlKeyCommand,
			 commandKey
		]
	}
}
