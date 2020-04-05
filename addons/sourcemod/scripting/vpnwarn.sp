#define PLUGIN_NAME           "VPNwarn"
#define PLUGIN_AUTHOR         "Snowy"
#define PLUGIN_DESCRIPTION    "Uses GFL VPN API service to determine whether an IP is a VPN"
#define PLUGIN_VERSION        "1.1"
#define PLUGIN_URL            ""

#include <colors_csgo>
#include <sourcemod>
#include <sdktools>
#include <ripext>

#pragma semicolon 1

#pragma newdecls required

ConVar g_cvURL, g_cvEndPoint, g_cvToken, g_cvEnablePrint, g_cvObject, g_cvKick;

char g_sURL[128], g_sEndPoint[128], g_sToken[128], g_sObject[128];
bool g_bIsBlocked[MAXPLAYERS+1] = {false, ...};
bool g_bEnablePrint, g_bKick;

HTTPClient hHTTPClient;

public Plugin myinfo =
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
};

public void OnPluginStart()
{
	g_cvURL =			CreateConVar("vpn_api_url", "google.com", "URL for the REST API.");
	g_cvEndPoint =		CreateConVar("vpn_endpoint_url", "something", "EndPoint for the API");
	g_cvToken =			CreateConVar("vpn_token", "", "Token to access the API");
	g_cvObject =		CreateConVar("vpn_object", "blocked", "The object in JSON to fetch the value");
	g_cvKick =			CreateConVar("vpn_kick", "0", "Whether or not to kick the VPN user when they join the server. 1 = kick, 0 = don't kick");

	g_cvEnablePrint = 	CreateConVar("vpn_enable_print", "1", "Enable or disable printing messages");
	
	RegAdminCmd("sm_fvpncheck", Command_Forcecheck, ADMFLAG_ROOT, "Force check a client");
	RegAdminCmd("sm_vpncheck", Command_VPNcheck, ADMFLAG_GENERIC, "Individually check if a client is using a VPN");
	
	LoadTranslations("common.phrases");
	AutoExecConfig(true, "GFL-VPN");
}

public void OnConfigsExecuted()
{
	// GetValues
	GetValues();
	
	// Hook ConVar changes
	g_cvURL.AddChangeHook(OnConVarChange);
	g_cvEndPoint.AddChangeHook(OnConVarChange);
	g_cvToken.AddChangeHook(OnConVarChange);
	g_cvEnablePrint.AddChangeHook(OnConVarChange);
	g_cvObject.AddChangeHook(OnConVarChange);
	g_cvKick.AddChangeHook(OnConVarChange);
}

public void OnConVarChange(ConVar CVar, const char[] oldVal, const char[] newVal)
{
	// GetValues
	GetValues();
}

public void OnClientConnected(int client) 
{
	// Reset client bool
	g_bIsBlocked[client] = false;
}

public void OnClientDisconnect(int client) 
{
	// Reset client bool
	g_bIsBlocked[client] = false;
}

public void OnClientPostAdminCheck(int client)
{
	if (IsFakeClient(client)) {
		return;
	}
	
	// Initiate VPN check
	VPN_Check(client);
	
	// Notify joined admins about current VPN users if any
	if (g_bEnablePrint)
	{
		if (IsValidAdmin(client, "b"))
			CreateTimer(45.0, NotifyAdmin, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action NotifyAdmin(Handle timer, any userID)
{
	int client = GetClientOfUserId(userID);
	int VPNcount = 0;
	
	if (!IsValidClient(client))
		return;
		
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
		{
			if (g_bIsBlocked[i])
			{
				// Get blocked user info
				char steamID[64];
				GetClientAuthId(i, AuthId_Engine, steamID, sizeof(steamID));
				int identifier = GetClientUserId(i);
				
				PrintToConsole(client, "[GFL-VPN] %N (%s) (#%i) is using a VPN", i, steamID, identifier);
				VPNcount++;
			}
		}
	}
	if (VPNcount >= 1)
		CPrintToChat(client, "\x01[\x07GFL-VPN\x01] \x04%i player(s) have been flagged for using a VPN, check console for more info", VPNcount);
}

// --------------
// Main Function
// --------------
stock void VPN_Check(int client)
{
	char ip[32], steamID64[64], endPointURL[256];
	
	// Get client info
	GetClientAuthId(client, AuthId_SteamID64, steamID64, sizeof(steamID64));
	GetClientIP(client, ip, sizeof(ip));
	
	// Replace info in endpoint URL
	endPointURL = g_sEndPoint;
	ReplaceString(endPointURL, sizeof(endPointURL), "{STEAMID}", steamID64);
	ReplaceString(endPointURL, sizeof(endPointURL), "{IP}", ip);
	
	// Set hHTTPClient info
	hHTTPClient.SetHeader("Authorization", g_sToken);
	hHTTPClient.Get(endPointURL, OnHTTPResponse, GetClientUserId(client));
}

public void OnHTTPResponse(HTTPResponse response, any data)
{
	// Retrieve client
	int client = GetClientOfUserId(data);
	
	if (!client)
		return;
		
	// Get client info
	char steamID64[64], ip[32];
	GetClientAuthId(client, AuthId_SteamID64, steamID64, sizeof(steamID64));
	GetClientIP(client, ip, sizeof(ip));
	
	// Determine response status
	if (response.Status != HTTPStatus_OK)
	{
		VPNLog("[ERROR] GET request (Error code: %d, Name: %N, SteamID: %s, IP: %s)", response.Status, client, steamID64, ip);
		return;
	}
	
	// Determine response data
	if (response.Data == null)
	{
		VPNLog("[ERROR] No response recieved (Name: %N, SteamID: %s, IP: %s)", client, steamID64, ip);
		return;
	}
	
	// View data as JSON
	JSONObject result = view_as<JSONObject>(response.Data);
	g_bIsBlocked[client] = result.GetBool(g_sObject);
	
	if (g_bIsBlocked[client])
	{
		// Kick client if vpn_kick is set to "1"
		if (g_bKick)
		{
			KickClient(client, "You have been kicked because you are using a VPN");
			VPNLog("Name: %N, SteamID: %s, IP: %s tried to join the server with a VPN", client, steamID64, ip);
			return;
		}
		
		VPNLog("Name: %N, SteamID: %s, IP: %s joined the server with a VPN", client, steamID64, ip);
		
		// Print to admins that someone joined with a VPN
		if (g_bEnablePrint)
			PrintToAdmins(client, "b");
	}
	/* Debugging
	else
		VPNLog("Name: %N, SteamID: %s, IP: %s joined the server without a VPN", client, steamID64, ip);
	*/
}

// --------------
// Command
// --------------
public Action Command_VPNcheck(int client, int args)
{
	if (args == 0)
		CPrintToChat(client, "\x01[\x07GFL-VPN\x01] \x04%N \x10is %s a VPN.", client, g_bIsBlocked[client] ? "using" : "not using");
		
	if (args == 1)
	{
		char arg1[65];
		GetCmdArg(1, arg1, sizeof(arg1));
		int target = FindTarget(client, arg1, false, false);
		if (target == -1)
		{
			return Plugin_Handled;
		}
		
		CPrintToChat(client, "\x01[\x07GFL-VPN\x01] \x04%N \x10is %s a VPN.",target, g_bIsBlocked[target] ? "using" : "not using");
	}
	
	return Plugin_Handled;
}

public Action Command_Forcecheck(int client, int args)
{
	if (args == 0)
	{	
		VPN_Check(client);
		CPrintToChat(client, "\x01[\x07GFL-VPN\x01] \x04%N \x10is %s a VPN.", client, g_bIsBlocked[client] ? "using" : "not using");
	}
		
	if (args == 1)
	{
		char arg1[65];
		GetCmdArg(1, arg1, sizeof(arg1));
		int target = FindTarget(client, arg1, false, false);
		if (target == -1)
		{
			return Plugin_Handled;
		}
		VPN_Check(target);
		CPrintToChat(client, "\x01[\x07GFL-VPN\x01] \x04%N \x10is %s a VPN.",target, g_bIsBlocked[target] ? "using" : "not using");
	}
	
	return Plugin_Handled;
}
// --------------
// Stocks
// --------------
stock void GetValues()
{
	// Retrieve CVars value
	g_cvURL.GetString(g_sURL, sizeof(g_sURL));
	g_cvEndPoint.GetString(g_sEndPoint, sizeof(g_sEndPoint));
	g_cvToken.GetString(g_sToken, sizeof(g_sToken));
	g_bEnablePrint = g_cvEnablePrint.BoolValue;
	g_cvObject.GetString(g_sObject, sizeof(g_sObject));
	g_bKick = g_cvKick.BoolValue;
	
	// Create hHTTPClient
	if (hHTTPClient != null)
		delete hHTTPClient;
	
	hHTTPClient = new HTTPClient(g_sURL);
}

stock bool IsValidClient(int client, bool bAlive = false)
{
	if (client >= 1 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client) && (bAlive == false || IsPlayerAlive(client)))
		return true;

	return false;
}

stock void PrintToAdmins(int client, const char[] flags) 
{
	char steamID[64];
	GetClientAuthId(client, AuthId_Engine, steamID, 64);
	
	int userid = GetClientUserId(client);
	
	for (int i = 1; i <= MaxClients; i++) 
	{ 
		if (IsValidClient(i) && IsValidAdmin(i, flags)) 
		{ 
			CPrintToChat(i, "\x01[\x07GFL-VPN\x01] \x04%N \x05(%s) \x10has joined the server via a VPN!", client, steamID);
			PrintToConsole(i, "[GFL-VPN] %N (%s) (#%i) has joined the server via a VPN!", client, steamID, userid);
		} 
	} 
}

stock bool IsValidAdmin(int client, const char[] flags) 
{ 
	int ibFlags = ReadFlagString(flags); 
	if ((GetUserFlagBits(client) & ibFlags) == ibFlags) 
	{ 
		return true; 
	} 
	if (GetUserFlagBits(client) & ADMFLAG_ROOT) 
	{ 
		return true; 
	} 
	return false; 
}   

stock void VPNLog(const char[] message, any ...)
{
	char date[32], sMessage[128], mapName[64];
	FormatTime(date, sizeof(date), "%d/%m/%Y %H:%M:%S", GetTime());
	VFormat(sMessage, sizeof(sMessage), message, 2);
	GetCurrentMap(mapName, sizeof(mapName));
	
	static char LogPath[PLATFORM_MAX_PATH];
	if(LogPath[0] == '\0')
		BuildPath(Path_SM, LogPath, sizeof(LogPath), "logs/connections/GFL_VPNLogs.log");
		
	File logfile = OpenFile(LogPath, "a");
	
	logfile.WriteLine("%s | %s | %s", date, mapName, sMessage);
	
	delete logfile;
}