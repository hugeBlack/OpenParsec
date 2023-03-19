class NetworkHandler
{
	public static var clinfo:ClientInfo? = nil
}

struct ErrorInfo:Decodable
{
	var error:String
//	var codes:Array
}

struct ClientInfo:Decodable
{
	var instance_id:String
	var user_id:Int
	var session_id:String
	var host_peer_id:String
}

struct UserInfo:Decodable
{
	var id:Int
	var name:String
	var warp:Bool
	var external_id:String
	var external_provider:String
	var team_id:String
}

struct HostInfo:Decodable
{
	var user:UserInfo
	var peer_id:String
	var game_id:String
	var description:String
	var max_players:Int
	var mode:String
	var name:String
	var event_name:String
	var players:Int
//	var public:Bool
	var guest_access:Bool
	var online:Bool
//	var self:Bool
	var build:String
}

struct HostInfoList:Decodable
{
	var data:Array<HostInfo>?
	var has_more:Bool
}
