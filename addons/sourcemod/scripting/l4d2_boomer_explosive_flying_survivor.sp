#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <dhooks>
#include <l4d2util>

#define CVAR_FLAGS		FCVAR_NOTIFY

#define GAMEDATA    "Miuwiki_TankHit"

Handle g_hDetour;
Handle g_hSDK_Call_FlyPlayer;
float
    g_explosive_high = 500.0,
    g_explosive_fxy  = 100.0;

ConVar
    gforce_high,
    gforce_xy,
    GOnForce;

bool
    OnForce = true;

public Plugin myinfo = 
{
	name 			= "l4d2_boomer_explosive_flying_survivor",
	author 			= "77",
	description 	= "Boomer炸飞幸存者.",
	version 		= "1.0",
	url 			= "N/A"
}

public void OnPluginStart()
{
	LoadGameData();

	gforce_high	= CreateConVar("l4d2_boomer_explosive_force_high",	"500.0", "Boomer炸飞幸存者的高度力度.", CVAR_FLAGS, true, 100.0);
	gforce_xy	= CreateConVar("l4d2_boomer_explosive_force_xy",	"100.0", "Boomer炸飞幸存者的水平力度.", CVAR_FLAGS, true, 100.0);
	GOnForce	= CreateConVar("l4d2_boomer_explosive_force_on",	"1",	 "Boomer炸飞幸存者的硬直 (1 = 启用, 0 = 禁用) [若禁用则炸飞时无硬直, 空中也可以开枪].", CVAR_FLAGS, true, 0.0, true, 1.0);

	gforce_high.AddChangeHook(ConVarChanged);
	gforce_xy.AddChangeHook(ConVarChanged);
	GOnForce.AddChangeHook(ConVarChanged);

	AutoExecConfig(true, "l4d2_boomer_explosive_flying_survivor");
}

public void ConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	GetCvars();
}

void GetCvars()
{
    g_explosive_high = gforce_high.FloatValue;
    g_explosive_fxy  = gforce_xy.FloatValue;
    OnForce          = GOnForce.BoolValue;
}

void LoadGameData()
{
    char sPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sPath, sizeof(sPath), "gamedata/%s.txt", GAMEDATA);
    if( FileExists(sPath) == false ) SetFailState("\n==========\nMissing required file: \"%s\".\nRead installation instructions again.缺少Miuwiki_TankHit.txt\n==========", sPath);

    Handle hGameData = LoadGameConfigFile(GAMEDATA);
    if( hGameData == null ) SetFailState("Failed to load \"%s.txt\" gamedata.", GAMEDATA);

    // Detour
    g_hDetour = DHookCreateFromConf(hGameData, "CTankClaw::OnPlayerHit");
    if( !g_hDetour )
        SetFailState("Failed to find \"CTankClaw::OnPlayerHit\" signature.");
    //SDKCALL
    StartPrepSDKCall(SDKCall_Player);
    if(PrepSDKCall_SetFromConf(hGameData, SDKConf_Signature, "CTerrorPlayer::Fling") == false)
        SetFailState("Failed to find signature: CTerrorPlayer::Fling");
        //其余参数按照call的函数设置，如果是SDKCall_Player类型第一个参数只能是client或者entity的索引。
    PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
    PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer);
    PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
    g_hSDK_Call_FlyPlayer = EndPrepSDKCall();
    if(g_hSDK_Call_FlyPlayer == null)
        SetFailState("Failed to create SDKCall: Fling");
    delete hGameData;
}

public Action L4D2_OnStagger(int target, int source)
{
    if (IsValidInfected(source))
    {
        int sourceClass = GetInfectedClass(source);

        if (sourceClass == L4D2Infected_Boomer)
        {
            if (IsS(target) && IsPlayerAlive(target) && IsPlayerState(target))
            {
                float eforce[3], idis[3], sdis[3], sub_dis[2];
                GetClientAbsOrigin(source, idis);
                GetClientAbsOrigin(target, sdis);
                sub_dis[0] = sdis[0] - idis[0];
                sub_dis[1] = sdis[1] - idis[1];

                bool CanCan = true;
                if (JC(sub_dis[0]) < 20.0)
                {
                    if (JC(sub_dis[1]) > 60.0)
                    {
                        CanCan = false;
                        eforce[0] = 0.0;
                        eforce[1] = JA(sub_dis[1]) * g_explosive_fxy;
                    }
                    else
                    {
                        sub_dis[0] = JA(sub_dis[0]) * 20.0;
                    }
                }
                if (JC(sub_dis[1]) < 20.0)
                {
                    if (JC(sub_dis[0]) > 60.0)
                    {
                        CanCan = false;
                        eforce[0] = JA(sub_dis[0]) * g_explosive_fxy;
                        eforce[1] = 0.0;
                    }
                    else
                    {
                        sub_dis[1] = JA(sub_dis[1]) * 20.0;
                    }
                }
                if (CanCan)
                {
                    float ftemp0 = 1.0 + get_two(JC(sub_dis[1])) / get_two(JC(sub_dis[0]));
                    float ftemp1 = 1.0 + get_two(JC(sub_dis[0])) / get_two(JC(sub_dis[1]));
                    eforce[0] = JA(sub_dis[0]) * g_explosive_fxy / (get_sqrt(ftemp0));
                    eforce[1] = JA(sub_dis[1]) * g_explosive_fxy / (get_sqrt(ftemp1));
                }
                eforce[2] = g_explosive_high;

                //PrintToChatAll("%N  %.2f | %.2f | %.2f", source, idis[0], idis[1], idis[2]);
                //PrintToChatAll("%N  %.2f | %.2f | %.2f", target, sdis[0], sdis[1], sdis[2]);
                //PrintToChatAll("%N  %.2f | %.2f", target, sub_dis[0], sub_dis[1]);
                //PrintToChatAll("%N  %.2f | %.2f | %.2f", target, eforce[0], eforce[1], eforce[2]);

                if (OnForce)
                {
                    SDKCall(g_hSDK_Call_FlyPlayer, target, eforce, 76, source, 3.0);
                }
                else
                {
                    SDKCall(g_hSDK_Call_FlyPlayer, target, eforce, DMG_CLUB, source, 0.5);
                }
                return Plugin_Handled;
            }
        }
    }

    return Plugin_Continue;
}

bool IsS(int client)
{
	return (client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == 2);
}

bool IsPlayerState(int client)
{
    return !GetEntProp(client, Prop_Send, "m_isIncapacitated") && !GetEntProp(client, Prop_Send, "m_isHangingFromLedge");
}

float JC(float n)
{
    if (n < 0.0)
    {
        return (n * (- 1.0));
    }
    return n;
}

float JA(float n)
{
    if (n < 0.0)
    {
        return (- 1.0);
    }
    return 1.0;
}

float get_sqrt(float n)
{
    for (int i = 0; ; i++)
    {
        if (JC(n) >= get_two(float(i)) && JC(n) < get_two(float(i + 1)))
        {
            return float(i);
        }
    }
}

float get_two(float n)
{
    return (n * n);
}