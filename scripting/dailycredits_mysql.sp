#pragma semicolon 1

#define PLUGIN_AUTHOR "Simon -edit by Nachtfrische"
#define PLUGIN_VERSION "1.7.1"

#include <sourcemod>
#include <sdktools>
#include <store>
#include <multicolors>

#pragma newdecls required

Database db;
ConVar g_hDailyEnable;
ConVar g_hDailyCredits;
ConVar g_hDailyBonus;
ConVar g_hDailyMax;
ConVar g_hDailyReset;
char CurrentDate[20];

public Plugin myinfo = 
{
	name = "[Store] Daily Credits", 
	author = PLUGIN_AUTHOR, 
	description = "Daily credits for regular players with MySQL support.", 
	version = PLUGIN_VERSION, 
	url = "yash1441@yahoo.com"
};

public void OnPluginStart()
{
	LoadTranslations("dailycredits.phrases");
	CreateConVar("sm_daily_credits_version", PLUGIN_VERSION, "Daily Credits Version", FCVAR_DONTRECORD | FCVAR_NOTIFY | FCVAR_REPLICATED | FCVAR_SPONLY);
	g_hDailyEnable = CreateConVar("sm_daily_credits_enable", "1", "Enable Daily Credits? 0 = disable, 1 = enable", 0, true, 0.0, true, 1.0);
	g_hDailyCredits = CreateConVar("sm_daily_credits_amount", "10", "Amount of credits you recieve.", 0, true, 0.0);
	g_hDailyBonus = CreateConVar("sm_daily_credits_bonus", "2", "Increase / Addition of the credits on consecutive days.", 0, true, 0.0);
	g_hDailyMax = CreateConVar("sm_daily_credits_max", "50", "Maximum amount of credits that you can get daily.", 0, true, 0.0);
	g_hDailyReset = CreateConVar("sm_daily_credits_resetperiod", "7", "Amount of days after which the streak should reset itself. Set to 0 to disable.", 0, true, 0.0);
	
	AutoExecConfig(true, "dailycredits");
	RegConsoleCmd("sm_daily", Cmd_Daily);
	RegConsoleCmd("sm_dailies", Cmd_Daily);
	FormatTime(CurrentDate, sizeof(CurrentDate), "%Y%m%d"); // Save current date in variable
	InitializeDB();
}

public void InitializeDB()
{
	char Error[255];
	db = SQL_Connect("dailycredits", true, Error, sizeof(Error));
	SQL_SetCharset(db, "utf8");
	if (db == INVALID_HANDLE)
	{
		SetFailState(Error);
	}
	SQL_TQuery(db, SQLErrorCheckCallback, "CREATE TABLE IF NOT EXISTS players (steam_id VARCHAR(20) UNIQUE, last_connect INT(12), bonus_amount INT(12));");
}

public Action Cmd_Daily(int client, int args)
{
	if (!GetConVarBool(g_hDailyEnable))return Plugin_Handled;
	if (!IsValidClient(client))return Plugin_Handled;
	char steamId[32];
	if (GetClientAuthId(client, AuthId_Steam2, steamId, sizeof(steamId)))
	{
		char buffer[200];
		Format(buffer, sizeof(buffer), "SELECT * FROM players WHERE steam_id = '%s'", steamId);
		SQL_LockDatabase(db);
		DBResultSet query = SQL_Query(db, buffer);
		SQL_UnlockDatabase(db);
		if (SQL_GetRowCount(query) == 0)
		{
			delete query;
			GiveCredits(client, true);
		}
		else
		{
			delete query;
			GiveCredits(client, false);
		}
	}
	else LogError("Failed to get Steam ID");
	
	return Plugin_Handled;
}

stock void GiveCredits(int client, bool FirstTime)
{
	char buffer[200];
	char steamId[32];
	if (GetClientAuthId(client, AuthId_Steam2, steamId, sizeof(steamId)))
	{
		if (FirstTime)
		{
			Store_SetClientCredits(client, Store_GetClientCredits(client) + GetConVarInt(g_hDailyCredits));
			CPrintToChatEx(client, client, "%t", "CreditsRecieved", GetConVarInt(g_hDailyCredits));
			Format(buffer, sizeof(buffer), "INSERT IGNORE INTO players (steam_id, last_connect, bonus_amount) VALUES ('%s', %d, 1)", steamId, StringToInt(CurrentDate));
			SQL_TQuery(db, SQLErrorCheckCallback, buffer);
		}
		else
		{
			Format(buffer, sizeof(buffer), "SELECT * FROM players WHERE steam_id = '%s'", steamId);
			SQL_LockDatabase(db);
			DBResultSet query = SQL_Query(db, buffer);
			SQL_UnlockDatabase(db);
			SQL_FetchRow(query);
			int date2 = SQL_FetchInt(query, 1);
			int bonus = SQL_FetchInt(query, 2);
			delete query;
			int date1 = StringToInt(CurrentDate);
			int resetDaysSetting = GetConVarInt(g_hDailyReset);
			
			//streak is currently continuing
			if ((date1 - date2) == 1)
			{
				int TotalCredits = GetConVarInt(g_hDailyCredits) + (bonus * GetConVarInt(g_hDailyBonus));
				if (TotalCredits > GetConVarInt(g_hDailyMax))TotalCredits = GetConVarInt(g_hDailyMax);
				Store_SetClientCredits(client, Store_GetClientCredits(client) + TotalCredits);
				
				if (bonus >= resetDaysSetting)
				{
					CPrintToChatEx(client, client, "%t", "LastCreditsRecieved", TotalCredits);
					Format(buffer, sizeof(buffer), "UPDATE players SET last_connect = %i, bonus_amount = %i WHERE steam_id = '%s'", date1, 1, steamId);
					CPrintToChatEx(client, client, "%t", "ResetDays", resetDaysSetting);
				}
				else
				{
					CPrintToChatEx(client, client, "%t", "CreditsRecieved", TotalCredits);
					Format(buffer, sizeof(buffer), "UPDATE players SET last_connect = %i, bonus_amount = %i WHERE steam_id = '%s'", date1, bonus + 1, steamId);
					CPrintToChatEx(client, client, "%t", "CurrentDay", bonus);
				}
				SQL_TQuery(db, SQLErrorCheckCallback, buffer);
			}
			//already recieved credits today
			else if ((date1 - date2) == 0)
			{
				CPrintToChatEx(client, client, "%t", "BackTomorrow");
			}
			//streak ended
			else if ((date1 - date2) > 1)
			{
				CPrintToChatEx(client, client, "%t", "StreakEnded", bonus);
				Store_SetClientCredits(client, Store_GetClientCredits(client) + GetConVarInt(g_hDailyCredits));
				CPrintToChatEx(client, client, "%t", "CreditsRecieved", GetConVarInt(g_hDailyCredits));
				Format(buffer, sizeof(buffer), "UPDATE players SET last_connect = %i, bonus_amount = 1 WHERE steam_id = '%s'", date1, steamId);
				SQL_TQuery(db, SQLErrorCheckCallback, buffer);
			}
		}
	}
	else LogError("Failed to get Steam ID");
}

stock bool IsValidClient(int client)
{
	if (client <= 0)return false;
	if (client > MaxClients)return false;
	if (!IsClientConnected(client))return false;
	return IsClientInGame(client);
}

public void SQLErrorCheckCallback(Handle owner, Handle hndl, const char[] error, any data)
{
	if (!StrEqual(error, ""))
		LogError(error);
} 