#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <dhooks>

#include <neotokyo>

#define PLUGIN_VERSION "0.1.0"

#define NEO_MAX_PLAYERS 32
#define VTABLE_OFFSET_RELOAD 235

DynamicHook dh = null;

// These must be in the same order as the neotokyo include weapon_primary entries.
// Duplicated entries are usually the silenced variants of the same gun.
char g_sReloadSounds_Primary[][] = {
    "",  // ghost; skip
    "weapons/mpn45/mpn45_reload.wav",
    "weapons/srm/srm_reload.wav",
    "weapons/srm/srm_reload.wav",
    "weapons/Jitte/jitte_reload.wav",
    "weapons/Jitte/jitte_reload.wav",
    "weapons/zr68/zr68_reload.wav",
    "weapons/zr68/zr68_reload.wav",
    "weapons/zr68/zr68L_Reload.wav",
    // In reality, it's one of the multiple random variants,
    // but this is good enough for now.
    "weapons/murata/murata_insert_shell1.wav",
    "weapons/m41/m41_reload.wav",
    "weapons/m41/m41_reload.wav",
    "weapons/mx/mx_reload.wav",
    "weapons/mx/mx_reload.wav",
    "weapons/aa13/aa13_reload.wav",
    "weapons/srs/srs_reload.wav",
    "weapons/pz/pz_reload.wav",
};
// These must be in the same order as the neotokyo include weapons_secondary entries.
char g_sReloadSounds_Secondary[][] = {
    "weapons/tachi/tachi_reload.wav",
    "weapons/milso/milso_reload.wav",
    "weapons/kyla/kyla_reload.wav",
};

public Plugin myinfo = {
    name = "NT Audible Reloads",
    description = "Hear the reload sounds of other players.",
    author = "Rain",
    version = PLUGIN_VERSION,
    url = "https://github.com/Rainyan/sourcemod-nt-audible-reloads"
};

public void OnPluginStart()
{
    dh = DHookCreate(VTABLE_OFFSET_RELOAD, HookType_Entity, ReturnType_Bool, ThisPointer_CBaseEntity);
    if (dh == null)
    {
        SetFailState("Failed to create detour for offset: %d", VTABLE_OFFSET_RELOAD);
    }
}

public void OnMapStart()
{
    char filebuff[PLATFORM_MAX_PATH];
    int i;
    for (i = 0; i < sizeof(g_sReloadSounds_Primary); ++i)
    {
        // Skipped entries
        if (strlen(g_sReloadSounds_Primary[i]) == 0)
        {
            continue;
        }
        // FileExists is based on root gamedir, but sound functions
        // auto-append the "sound" folder, so use a placeholder variable
        // here to confirm the file exists.
        Format(filebuff, sizeof(filebuff), "sound/%s", g_sReloadSounds_Primary[i]);
        if (!FileExists(filebuff))
        {
            SetFailState("Reload sound doesn't exist on server disk: \"%s\"",
                g_sReloadSounds_Primary[i]);
        }
        if (!PrecacheSound(g_sReloadSounds_Primary[i]))
        {
            SetFailState("Failed to precache sound: \"%s\"",
                g_sReloadSounds_Primary[i]);
        }
    }
    for (i = 0; i < sizeof(g_sReloadSounds_Secondary); ++i)
    {
        Format(filebuff, sizeof(filebuff), "sound/%s", g_sReloadSounds_Secondary[i]);
        if (!FileExists(filebuff))
        {
            SetFailState("Reload sound doesn't exist on server disk: \"%s\"",
                g_sReloadSounds_Secondary[i]);
        }
        if (!PrecacheSound(g_sReloadSounds_Secondary[i]))
        {
            SetFailState("Failed to precache sound: \"%s\"",
                g_sReloadSounds_Secondary[i]);
        }
    }
}

public void OnEntityCreated(int entity)
{
    if (!IsValidEdict(entity))
    {
        return;
    }
    char classname[32];
    if (!GetEdictClassname(entity, classname, sizeof(classname)))
    {
        return;
    }
    if (StrContains(classname, "weapon_") != 0)
    {
        return;
    }
    // Post hook, because must know whether the reloads are successful or not (retval).
    // Entity hooks are auto-removed when the entity is destroyed.
    if (dh.HookEntity(Hook_Post, entity, OnReload) == INVALID_HOOK_ID)
    {
        SetFailState("Failed to hook: %s", classname);
    }
}

// For a given Neotokyo weapon edict, passes the corresponding reload sound by reference.
// Returns boolean of whether a reload sound was found for the weapon.
bool GetReloadSoundOfWeapon(int weapon, char[] out_sound, const int out_sound_maxlen)
{
    if (!IsValidEdict(weapon))
    {
        return false;
    }

    char classname[32]; // TODO: max weaponname length
    if (!GetEdictClassname(weapon, classname, sizeof(classname)))
    {
        return false;
    }

    int i;
    for (i = 0; i < sizeof(weapons_primary); ++i)
    {
        if (StrEqual(classname, weapons_primary[i]))
        {
            return strcopy(out_sound, out_sound_maxlen, g_sReloadSounds_Primary[i]) > 0;
        }
    }

    for (i = 0; i < sizeof(weapons_secondary); ++i)
    {
        if (StrEqual(classname, weapons_secondary[i]))
        {
            return strcopy(out_sound, out_sound_maxlen, g_sReloadSounds_Secondary[i]) > 0;
        }
    }

    return false;
}

// For a given int array arr of size num_values, pass by refence to array out_arr all of its values that are not equal to unique_value_to_filter.
// Assumes out_arr will be of size num_values-1.
// Returns the number of elements passed into out_arr.
int FilterUniqueValueFromArray(const int[] arr, int num_values, int unique_value_to_filter, int[] out_arr)
{
    int num_out = 0;
    for (int i = 0; i < num_values; ++i)
    {
        if (arr[i] == unique_value_to_filter)
        {
            continue;
        }
        out_arr[num_out++] = arr[i];
    }
    return num_out;
}

// Detour of the weapon reload.
// The post-hook value of hReloadSuccessful returns true if the reload is successful
// (ie. has enough ammo, is allowed to reload...).
// Note: if you need to debug this with print statements, the print to chat sound channel
// triggering at the exact same time can actually cut off the sound effect;
// PrintToServer may be more useful for inside this detour with regard to audio debug.
public MRESReturn OnReload(int edict, DHookReturn hReloadSuccessful)
{
    if (!hReloadSuccessful.Value)
    {
        return MRES_Ignored;
    }

    if (!IsValidEdict(edict) || !HasEntProp(edict, Prop_Data, "m_hOwnerEntity"))
    {
        return MRES_Ignored;
    }

    int owner = GetEntPropEnt(edict, Prop_Data, "m_hOwnerEntity");
    if (owner <= 0 || owner > MaxClients || !IsClientInGame(owner))
    {
        return MRES_Ignored;
    }

    char audio_sample[PLATFORM_MAX_PATH];
    // Can happen if trying to reload something like the knife
    if (!GetReloadSoundOfWeapon(edict, audio_sample, sizeof(audio_sample)))
    {
        return MRES_Ignored;
    }

    float pos[3];
    GetClientAbsOrigin(owner, pos);

    int audience[NEO_MAX_PLAYERS];
    int num_audience = GetClientsInRange(pos, RangeType_Audibility, audience, sizeof(audience));

    // If there's nobody else around to hear the reload, don't bother with it.
    if (num_audience <= 1)
    {
        return MRES_Ignored;
    }

    int[] audience_sans_owner = new int[num_audience - 1];
    // Filter the gun owner, because they'll already hear their own reload
    num_audience = FilterUniqueValueFromArray(audience, num_audience, owner, audience_sans_owner);

    EmitSound(
        audience_sans_owner,
        num_audience,
        audio_sample,
        owner,
        // Need to set streaming type channel to avoid stepping over existing sounds
        SNDCHAN_STATIC,
        _,
        _,
        _,
        _,
        _,
        pos
    );

    return MRES_Ignored;
}