import Foundation
import SwiftUI

var appScheme:ColorScheme = .dark

struct GLBData
{
	let SessionKeyChainKey = "OPStoredAuthData"
}

class GLBDataModel
{
	static let shared = GLBData()
}

extension String
{
	static func fromBuffer(_ ptr:UnsafeMutablePointer<CChar>, length len:Int) -> String
	{
		// convert C char bytes using the UTF8 encoding
		let nsstr = NSString(bytes:ptr, length:len, encoding:NSUTF8StringEncoding)
		return nsstr! as String
	}
}


struct Queue<T> {
	private var elements: [T] = []
	private let maxLength: Int
	
	init(maxLength: Int) {
		self.maxLength = maxLength
	}
	
	mutating func enqueue(_ element: T) {
		if elements.count >= maxLength {
			let _ = dequeue()
		}
		elements.append(element)
	}
	
	mutating func dequeue() -> T? {
		guard !elements.isEmpty else {
			return nil
		}
		return elements.removeFirst()
	}
	
	func peek() -> T? {
		return elements.first
	}
	
	func isFull() -> Bool {
		return elements.count == maxLength
	}
	
	func isEmpty() -> Bool {
		return elements.isEmpty
	}
	
	var count: Int {
		return elements.count
	}
}

class VideoStream {
	private var stream = [UInt8]()
	
	public func pushAndGetNalu(_ data: Data) -> [[UInt8]] {
		let orgLength = stream.count
		var ans = [[UInt8]]()
		stream.append(contentsOf: [UInt8](data))
		
		var now = orgLength
		
		while now < stream.count - 4 {
			if stream[now..<now+4] == [0,0,0,1] && now > 0 {
				ans.append([UInt8](stream[0..<now]))
				stream.removeSubrange(0..<now)
				now = 4
			}
			now += 1
		}
		return ans
	}
}

class OpenGLHelpers {
	static let vertexShaderSource = """
#version 100
attribute vec4 position;
attribute vec2 texCoord;
varying vec2 v_TexCoord;
void main() {
	gl_Position = position;
	v_TexCoord = texCoord;
}
"""
	
	static let fragmentShaderSource = """
#version 100
precision mediump float;
varying vec2 v_TexCoord;
uniform sampler2D texture;
void main() {
	gl_FragColor = texture2D(texture, v_TexCoord);
}
"""
	
	static func createTexture(from image: UIImage) -> GLuint {
		guard let cgImage = image.cgImage else {
			fatalError("Failed to create CGImage")
		}
		
		let width = cgImage.width
		let height = cgImage.height
		
		let colorSpace = CGColorSpaceCreateDeviceRGB()
		let rawData = calloc(height * width * 4, MemoryLayout<GLubyte>.size)
		let bytesPerPixel = 4
		let bytesPerRow = bytesPerPixel * width
		let bitsPerComponent = 8
		
		let context = CGContext(
			data: rawData,
			width: width,
			height: height,
			bitsPerComponent: bitsPerComponent,
			bytesPerRow: bytesPerRow,
			space: colorSpace,
			bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
		)
		
		context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
		
		var textureID: GLuint = 0
		glGenTextures(1, &textureID)
		glBindTexture(GLenum(GL_TEXTURE_2D), textureID)
		glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
		glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
		glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
		glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
		
		glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA, GLsizei(width), GLsizei(height), 0, GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), rawData)
		
		free(rawData)
		return textureID
	}
	
	static var texUniform: Int32 = 1
	
	static func compileAndLinkShaderProgram() -> GLuint {
		func compileShader(_ source: String, type: GLenum) -> GLuint? {
			let shader = glCreateShader(type)
			var sourceString = (source as NSString).utf8String
			var sourceLength = GLint(source.count)
			glShaderSource(shader, 1, &sourceString, &sourceLength)
			glCompileShader(shader)
			
			var compileStatus: GLint = 0
			glGetShaderiv(shader, GLenum(GL_COMPILE_STATUS), &compileStatus)
			if compileStatus == GL_FALSE {
				var infoLogLength: GLint = 0
				glGetShaderiv(shader, GLenum(GL_INFO_LOG_LENGTH), &infoLogLength)
				if infoLogLength > 0 {
					let infoLog = String(repeating: "\0", count: Int(infoLogLength))
					glGetShaderInfoLog(shader, infoLogLength, nil, UnsafeMutablePointer(mutating: infoLog))
					print("Shader compile log: \(infoLog)")
				}
				glDeleteShader(shader)
				return nil
			}
			
			return shader
		}
		
		guard let vertexShader = compileShader(vertexShaderSource, type: GLenum(GL_VERTEX_SHADER)),
			  let fragmentShader = compileShader(fragmentShaderSource, type: GLenum(GL_FRAGMENT_SHADER)) else {
			fatalError("Failed to compile shaders")
		}
		
		let program = glCreateProgram()
		glAttachShader(program, vertexShader)
		glAttachShader(program, fragmentShader)
		
		glBindAttribLocation(program, 0, "position")
		glBindAttribLocation(program, 1, "texCoord")
		
		glLinkProgram(program)
		
		texUniform = glGetUniformLocation(program, "texture")
		
		var linkStatus: GLint = 0
		glGetProgramiv(program, GLenum(GL_LINK_STATUS), &linkStatus)
		if linkStatus == GL_FALSE {
			var infoLogLength: GLint = 0
			glGetProgramiv(program, GLenum(GL_INFO_LOG_LENGTH), &infoLogLength)
			if infoLogLength > 0 {
				let infoLog = String(repeating: "\0", count: Int(infoLogLength))
				glGetProgramInfoLog(program, infoLogLength, nil, UnsafeMutablePointer(mutating: infoLog))
				print("Program link log: \(infoLog)")
			}
			glDeleteProgram(program)
			fatalError("Failed to link program")
		}
		
		glDeleteShader(vertexShader)
		glDeleteShader(fragmentShader)
		
		return program
	}
	
}
