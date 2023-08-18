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
//	var external_id:String
//	var external_provider:String
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

struct SelfInfoData:Decodable
{
	var id:Int
	var name:String
	var email:String
	var warp:Bool
	var staff:Bool
	var team_id:String
	var is_confirmed:Bool
	var team_is_active:Bool
	var is_saml:Bool
	var is_gateway_enabled:Bool
	var is_relay_enabled:Bool
	var has_tfa:Bool
//	var app_config:Any
	var cohort_channel:String
}

struct SelfInfo:Decodable
{
	var data:SelfInfoData
}

struct FriendInfo:Decodable
{
	var user_id:Int
	var user_name:String
}

struct FriendInfoList:Decodable
{
	var data:Array<FriendInfo>?
	var has_more:Bool
}
