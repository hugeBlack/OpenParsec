import Foundation

struct SettingsHandler
{
	//public static var renderer:RendererType = .opengl
	public static var decoder:DecoderPref = .h264
	public static var streamProtocol:ProtocolPref = .stcp
	//public static var cursorMode:CursorMode = .touchpad
	//public static var cursorScale:Float = 1
	public static var noOverlay:Bool = false
	
	public static func load()
	{
		//if UserDefaults.standard.exists(forKey:"renderer")
		//	{ renderer = RendererType(rawValue:UserDefaults.standard.integer(forKey:"renderer"))! }
		if UserDefaults.standard.exists(forKey:"decoder")
			{ decoder = DecoderPref(rawValue:UserDefaults.standard.integer(forKey:"decoder"))! }
		if UserDefaults.standard.exists(forKey:"protocol")
			{ streamProtocol = ProtocolPref(rawValue:UserDefaults.standard.integer(forKey:"protocol"))! }
		//if UserDefaults.standard.exists(forKey:"cursorMode")
		//	{ cursorMode = CursorMode(rawValue:UserDefaults.standard.integer(forKey:"cursorMode"))! }
		//if UserDefaults.standard.exists(forKey:"cursorScale")
		//	{ cursorScale = UserDefaults.standard.float(forKey:"cursorScale") }
		if UserDefaults.standard.exists(forKey:"noOverlay")
			{ noOverlay = UserDefaults.standard.bool(forKey:"noOverlay") }
	}
	
	public static func save()
	{
		//UserDefaults.standard.set(renderer.rawValue, forKey:"renderer")
		UserDefaults.standard.set(decoder.rawValue, forKey:"decoder")
		UserDefaults.standard.set(streamProtocol.rawValue, forKey:"protocol")
		//UserDefaults.standard.set(cursorMode.rawValue, forKey:"cursorMode")
		//UserDefaults.standard.set(cursorScale, forKey:"cursorScale")
		UserDefaults.standard.set(noOverlay, forKey:"noOverlay")
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
