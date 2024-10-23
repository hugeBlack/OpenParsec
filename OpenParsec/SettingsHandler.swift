import Foundation

struct SettingsHandler
{
	//public static var renderer:RendererType = .opengl
	public static var resolution : ParsecResolution = ParsecResolution.resolutions[1]
	public static var decoder:DecoderPref = .h264
	public static var cursorMode:CursorMode = .touchpad
	public static var cursorScale:Float = 0.5
	public static var mouseSensitivity : Float = 1.0
	public static var noOverlay:Bool = false
	public static var hideStatusBar:Bool = true
	
	public static func load()
	{
		//if UserDefaults.standard.exists(forKey:"renderer")
		//	{ renderer = RendererType(rawValue:UserDefaults.standard.integer(forKey:"renderer"))! }
		if UserDefaults.standard.exists(forKey:"decoder")
			{ decoder = DecoderPref(rawValue:UserDefaults.standard.integer(forKey:"decoder"))! }
		if UserDefaults.standard.exists(forKey:"cursorMode")
			{ cursorMode = CursorMode(rawValue:UserDefaults.standard.integer(forKey:"cursorMode"))! }
		if UserDefaults.standard.exists(forKey:"cursorScale")
			{ cursorScale = UserDefaults.standard.float(forKey:"cursorScale") }
		if UserDefaults.standard.exists(forKey:"mouseSensitivity")
		{ mouseSensitivity = UserDefaults.standard.float(forKey:"mouseSensitivity") }
		if UserDefaults.standard.exists(forKey:"noOverlay")
			{ noOverlay = UserDefaults.standard.bool(forKey:"noOverlay") }
		if UserDefaults.standard.exists(forKey:"hideStatusBar")
		{ hideStatusBar = UserDefaults.standard.bool(forKey:"hideStatusBar") }
		
		if UserDefaults.standard.exists(forKey:"resolution") {
			for res in ParsecResolution.resolutions {
				if res.desc == UserDefaults.standard.string(forKey: "resolution") {
					resolution = res
					break
				}
			}
		}
	}
	
	public static func save()
	{
		//UserDefaults.standard.set(renderer.rawValue, forKey:"renderer")
		UserDefaults.standard.set(decoder.rawValue, forKey:"decoder")
		UserDefaults.standard.set(cursorMode.rawValue, forKey:"cursorMode")
		UserDefaults.standard.set(cursorScale, forKey:"cursorScale")
		UserDefaults.standard.set(mouseSensitivity, forKey: "mouseSensitivity")
		UserDefaults.standard.set(noOverlay, forKey:"noOverlay")
		UserDefaults.standard.set(resolution.desc, forKey:"resolution")
		UserDefaults.standard.set(hideStatusBar, forKey: "hideStatusBar")
	}
}

extension UserDefaults
{
	/**
	 * Checks if a specified key exists within this UserDefaults.
	 */
	func exists(forKey:String) -> Bool
	{
		return object(forKey:forKey) != nil
	}
}
