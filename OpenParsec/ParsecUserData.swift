
struct ParsecUserDataVideo : Codable {
	var encoderFPS : Int = 0
	var resolutionX : Int = 0
	var resolutionY : Int = 0
	var fullFPS : Bool = false
	var hostOS = 0
	var output = "none"
	var encoderMaxBitrate : Int = 50
}

struct ParsecUserDataVideoConfig : Codable {
	var virtualMicrophone : Int = 0
	var virtualTablet : Int = 0
	var video : [ParsecUserDataVideo] = [
		ParsecUserDataVideo(),
		ParsecUserDataVideo(),
		ParsecUserDataVideo()
	]
}

enum ParsecUserDataType : UInt32 {
	case getVideoConfig = 9
	case getAdapterInfo = 10
	case setVideoConfig = 11
}
