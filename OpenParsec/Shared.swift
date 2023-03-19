//
//  Shared.swift
//  OpenParsec
//
//  Created by Seçkin KÜKRER on 25.02.2023.
//

import Foundation

struct GLBData
{
	let SessionKeyChainKey = "OPStoredAuthData"
}

class GLBDataModel
{
	static let shared = GLBData()
}
