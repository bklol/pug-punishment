#include <sourcemod>
#include<pugsetup>
#include<redirect_core>

#tryinclude <sourcebanspp>
#if !defined _sourcebanspp_included
	#tryinclude <sourcebans>
#endif

#define SERVER 0

Handle sm_server_number;
Handle sm_server_ip;

Database g_dDatabase = null;

char g_szAuth[MAXPLAYERS + 1][32];
char serverip[64];
char sip[MAXPLAYERS + 1][64];

int MatchId[MAXPLAYERS + 1];
int TimeDisconnet[MAXPLAYERS + 1];
int servernumber;
int Seconds[MAXPLAYERS + 1];
int Sid[MAXPLAYERS + 1];
int esptime[MAXPLAYERS + 1];
int cbtime[MAXPLAYERS + 1];

bool showmenu[MAXPLAYERS + 1];
bool IsMatchEnd;
bool IsPlayer[MAXPLAYERS + 1];
bool IsFristTime[MAXPLAYERS + 1];

public void OnPluginStart()
{
	SQL_MakeConnection();
	HookEvent("player_spawn", Event_PlayerSpawn);
	sm_server_number=CreateConVar("sm_server_number", "-1", "ONE SERVER ONE NUMBER");
	sm_server_ip= CreateConVar("sm_server_ip", "-1", "SERVER IP");
	AutoExecConfig(true, "PugPunish");
}

public void OnMapStart()
{
	servernumber=GetConVarInt(sm_server_number);
	GetConVarString(sm_server_ip, serverip, sizeof(serverip));
	IsMatchEnd = true;
	CheckServerIssue();
}

void CheckServerIssue()
{
	char szQuery[512];
	FormatEx(szQuery, sizeof(szQuery), "SELECT `ip` FROM `serverissue` WHERE sid = '%s'",servernumber);
	g_dDatabase.Query(SQL_FetchServer_CB, szQuery);
}

public void SQL_FetchServer_CB(Database db, DBResultSet results, const char[] error, any data)
{
	
	if (results.FetchRow())
	{
		return;
	}
	else
	{
		char szQuery[512];
		FormatEx(szQuery, sizeof(szQuery), "INSERT INTO `serverissue` (`sid`,`ip`,`isend`,`players`) VALUES ('%i','%s','1','-1')",servernumber,serverip);
		g_dDatabase.Query(SQL_CheckForErrors, szQuery);
	}
}

public Action Event_PlayerSpawn(Event event, char[] name, bool dontBroadcast)
{
	int iClient = GetClientOfUserId(event.GetInt("userid"));
	if(!IsMatchEnd)
	{
		
		CreateTimer(1.5,IsInGame,iClient);
	}
	else
		IsPlayer[iClient] = false;
}
public Action IsInGame( Handle timer,int client)
{
	if(!IsPlayerAlive(client))
		return;
	IsPlayer[client] = true;
	if(IsFristTime[client])
	{
		IsFristTime[client]=!IsFristTime[client];
		PrintToChat(client,"你已进入比赛!请不要随意放弃比赛!随意放弃比赛将受到惩罚！");
	}
}

void SQL_MakeConnection()
{
	if (g_dDatabase != null)
		delete g_dDatabase;
	char szError[512];
	g_dDatabase = SQL_Connect("neko", true, szError, sizeof(szError));
	if (g_dDatabase == null)
	{
		SetFailState("Cannot connect to datbase error: %s", szError);
	}
}

public void OnClientPostAdminCheck(int client)
{
	if (!GetClientAuthId(client, AuthId_Steam2, g_szAuth[client], sizeof(g_szAuth)))
	{
		KickClient(client, "Verification problem, Please reconnect");
		return;
	}
	showmenu[client] = false;
	MatchId[client] = -1;
	TimeDisconnet[client] = -1;
	Seconds[client] = 60;
	IsPlayer[client] = false;
	IsFristTime[client] = false;
	
	char szQuery[512];
	FormatEx(szQuery, sizeof(szQuery), "SELECT `server`,`time` FROM `puguser` WHERE auth = '%s'",g_szAuth[client]);
	g_dDatabase.Query(SQL_FetchUser_CB, szQuery, GetClientSerial(client));
	
	FormatEx(szQuery, sizeof(szQuery), "SELECT `esp`,`cb` FROM `puglog` WHERE auth = '%s'",g_szAuth[client]);
	g_dDatabase.Query(SQL_FetchUserLog_CB, szQuery, GetClientSerial(client));
	
}

public void SQL_FetchUser_CB(Database db, DBResultSet results, const char[] error, any data)
{
	checkPlayerlive();
	
	int iClient = GetClientFromSerial(data);
	if (results.FetchRow())
	{
		Sid[iClient] = results.FetchInt(1);
		TimeDisconnet[iClient] = results.FetchInt(2);
		CheckIssue(iClient);
	}
	
}

public void SQL_FetchUserLog_CB(Database db, DBResultSet results, const char[] error, any data)
{
	int iClient = GetClientFromSerial(data);
	char szQuery[512];
	if (results.FetchRow())
	{
		esptime[iClient] = results.FetchInt(1);
		cbtime[iClient] = results.FetchInt(2);
		PrintToAdmins("注意玩家%N 累计逃跑%i次，累计返回 %i次",iClient,esptime[iClient],cbtime[iClient]);
	}
	else
	{
		FormatEx(szQuery, sizeof(szQuery), "INSERT INTO `puglog` (`auth`,`esp`,`cb`) VALUES ('%s','0','0')",g_szAuth[iClient]);
		g_dDatabase.Query(SQL_CheckForErrors, szQuery);
	}
}

void CheckIssue(int iClient)
{
	char szQuery[512];
	int now=GetTime();
	if( now - TimeDisconnet[iClient] > 600)
	{
		BanPlayer(iClient, 6, "因为逃离比赛而冷却");
		FormatEx(szQuery, sizeof(szQuery), "DELETE FROM `puguser` WHERE `auth` = '%s'", g_szAuth[iClient]);
		g_dDatabase.Query(SQL_CheckForErrors, szQuery, GetClientSerial(iClient));
		return;
	}
	if(Sid[iClient] == servernumber)
	{
		
		FormatEx(szQuery, sizeof(szQuery), "DELETE FROM `puguser` WHERE `auth` = '%s'", g_szAuth[iClient]);
		g_dDatabase.Query(SQL_CheckForErrors, szQuery, GetClientSerial(iClient));
		FormatEx(szQuery, sizeof(szQuery), "UPDATE `puglog` SET `cb` = '%i' WHERE `auth` = '%s'",cbtime[iClient]+1,g_szAuth[iClient]);
		g_dDatabase.Query(SQL_CheckForErrors, szQuery);
	}
	
	FormatEx(szQuery, sizeof(szQuery), "SELECT `players`,`isend` ,`ip`FROM  `serverissue` WHERE sid = '%i'",servernumber);
	g_dDatabase.Query(SQL_FetchMatch_CB, szQuery, GetClientSerial(iClient));
}

public void SQL_FetchMatch_CB(Database db, DBResultSet results, const char[] error, any data)
{
	char szQuery[512];
	int iClient = GetClientFromSerial(data);
	if (results.FetchRow())
	{
		int LivePlayer = results.FetchInt(1);
		int end = results.FetchInt(2);
		results.FetchString(0, sip[iClient], sizeof(sip));
		
		if(LivePlayer > 10 || end == 1)
		{
			BanPlayer(iClient, 6, "因为逃离比赛而冷却");
			FormatEx(szQuery, sizeof(szQuery), "DELETE FROM `puguser` WHERE `auth` = '%s'", g_szAuth[iClient]);
			g_dDatabase.Query(SQL_CheckForErrors, szQuery, GetClientSerial(iClient));
			return;
		}
	}
	
	AskReconnectOrKick(iClient);
}

public void PugSetup_OnLive()
{
	char szQuery[512];
	FormatEx(szQuery, sizeof(szQuery), "UPDATE `serverissue` SET  `isend`= '0' WHERE `servernumber` = '%i'",servernumber);
	g_dDatabase.Query(SQL_CheckForErrors, szQuery);
	IsMatchEnd=false;
	
}

public void PugSetup_OnForceEnd(int client)
{
	char szQuery[512];
	FormatEx(szQuery, sizeof(szQuery), "UPDATE `serverissue` SET `isend` = '1' WHERE `servernumber` = '%i'",servernumber);
	g_dDatabase.Query(SQL_CheckForErrors, szQuery);
	IsMatchEnd=true;
}

public void PugSetup_OnMatchOver(bool hasDemo, const char[] demoFileName)
{
	char szQuery[512];
	FormatEx(szQuery, sizeof(szQuery), "UPDATE `serverissue` SET `isend` = '1' WHERE `servernumber` = '%i'",servernumber);
	g_dDatabase.Query(SQL_CheckForErrors, szQuery);
	IsMatchEnd=true;
}

AskReconnectOrKick(int client)
{
	if(showmenu[client])
	{
		CreateTimer(1.00, cooldown,client,TIMER_REPEAT);
		showmenu[client]=!showmenu[client];
	}
	int min=Seconds[client]/60;
	int sec=Seconds[client]%60;
	Menu menu = new Menu(Handler_mianMenu);
	menu.SetTitle("选择时间[%i:%i]\n玩家须知:",min,sec);
	menu.AddItem("0","请不要抛弃你的队友",ITEMDRAW_DISABLED);
	menu.AddItem("1","请不要在比赛未结束时离开游戏",ITEMDRAW_DISABLED);
	menu.AddItem("2","返回之前比赛");
	menu.AddItem("3","我选择放弃比赛接受冷却时间");
	menu.Display(client, MENU_TIME_FOREVER);
	menu.ExitButton = false;
}

public Action cooldown(Handle timer,int client)
{
	AskReconnectOrKick(client);
	Seconds[client]--;
	if(Seconds[client]<=0){
		char szQuery[512];
		KickClient(client,"请先完成之前的比赛");
		FormatEx(szQuery, sizeof(szQuery), "DELETE FROM `puguser` WHERE `auth` = '%s'", g_szAuth[client]);
		g_dDatabase.Query(SQL_CheckForErrors, szQuery, GetClientSerial(client));
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

public int Handler_mianMenu(Menu menu, MenuAction action, int client,int itemNum)
{
	
	if (action == MenuAction_Select)
	{
		switch (itemNum)
		{
			case 2: ServerCommand("sm_redirect %N %s",client,sip[client]);
			
			case 3:
			{
				char szQuery[512];
				BanPlayer(client, 6, "因为逃离比赛而冷却");
				FormatEx(szQuery, sizeof(szQuery), "DELETE FROM `puguser` WHERE `auth` = '%s'", g_szAuth[client]);
				g_dDatabase.Query(SQL_CheckForErrors, szQuery, GetClientSerial(client));
			}
		}
	}
}
public OnClientDisconnect(int client)
{
	if(IsMatchEnd)
		return;
	checkPlayerlive();
	
	if(!IsPlayer[client])
		return;
	PrintToChatAll("玩家%N在比赛中途离开游戏,在规定时间内若未返回将接受惩罚",client);
	char szQuery[512];
	FormatEx(szQuery, sizeof(szQuery), "INSERT INTO `puguser` (`auth`,`server`,`time`) VALUES ('%s','%i','%i')",g_szAuth[client],servernumber,GetTime());
	g_dDatabase.Query(SQL_CheckForErrors, szQuery);
	
	FormatEx(szQuery, sizeof(szQuery), "UPDATE `puglog` SET `esp` = '%i' WHERE `auth` = '%s'",esptime[client]+1,g_szAuth[client]);
	g_dDatabase.Query(SQL_CheckForErrors, szQuery);
}

stock void BanPlayer(int client, int time, char[] reason)
{
	#if defined _sourcebanspp_included
		SBPP_BanPlayer(SERVER, client, time, reason);
	#else
		#if defined _sourcebans_included
			SBBanPlayer(SERVER, client, time, reason);
		#else
			BanClient(client, time, BANFLAG_AUTO, reason);
		#endif
	#endif
}

public void SQL_CheckForErrors(Database db, DBResultSet results, const char[] error, any data)
{	
	
	if (!StrEqual(error, ""))
	{
		LogError("Databse error, %s", error);
		return;
	}
}

stock void PrintToAdmins(const char[] msg, any ...)
{
	char buffer[300];
	VFormat(buffer, sizeof(buffer), msg, 2);
	
	for(int i = 1; i <= MaxClients; i++)
	{
		if(CheckCommandAccess(i, "", ADMFLAG_KICK) && IsValidClient(i))
		{
			PrintToChat(i, buffer);
		}
	}
}

void checkPlayerlive()
{
	int num = 0;
	for(int i = 1; i <= MaxClients; i++)
	{
		if( IsValidClient(i) && GetClientTeam(i) != 3)
			num++;
	}
	
	char szQuery[512];
	FormatEx(szQuery, sizeof(szQuery), "UPDATE `serverissue` SET `players` = '%i' WHERE `servernumber` = '%i'",servernumber,num);
	g_dDatabase.Query(SQL_CheckForErrors, szQuery);
}

stock bool IsValidClient( client )
{
	if ( client < 1 || client > MaxClients ) return false;
	if ( !IsClientConnected( client )) return false;
	if ( !IsClientInGame( client )) return false;
	if ( IsFakeClient(client)) return false;
	return true;
}
