#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <dhooks>

#include <neotokyo>

#define PLUGIN_VERSION "0.4.1"

#define NEO_MAX_PLAYERS 32
#define NEO_MAX_WEPNAME_STRLEN 19
#define VTABLE_OFFSET_RELOAD 235
// "<" is CHAR_DIRECTIONAL, ")" is CHAR_SPATIALSTEREO.
// The directionality doesn't really work with the source material, but make the best out of it.
#define SOUND_CHARACTERS "<)"
// Default level of 75 felt too loud, and the next named value at 60 too quiet,
// so this is a value in-between those two.
#define SNDLEVEL_RELOAD 67
// In Hammer units
#define MAX_AUDIBLE_DISTANCE 512.0

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
    "",  // supa; skip
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
    char soundname[PLATFORM_MAX_PATH];
    char filebuff[PLATFORM_MAX_PATH];
    int i;
    for (i = 0; i < sizeof(weapons_primary); ++i)
    {
        if (!GetReloadSoundOfWeapon(weapons_primary[i], soundname, sizeof(soundname)))
        {
            continue;
        }
        // FileExists is relative to root gamedir, but sound functions
        // auto-append the "sound" folder, so use a placeholder variable
        // here to confirm the file exists.
        Format(filebuff, sizeof(filebuff), "sound/%s", soundname);
        if (!FileExists(filebuff))
        {
            SetFailState("Reload sound doesn't exist on server disk: \"%s\"", filebuff);
        }
        Format(filebuff, sizeof(filebuff), "%s%s", SOUND_CHARACTERS, soundname);
        if (!PrecacheSound(soundname))
        {
            SetFailState("Failed to precache sound: \"%s\"", soundname);
        }
    }
    for (i = 0; i < sizeof(weapons_secondary); ++i)
    {
        if (!GetReloadSoundOfWeapon(weapons_secondary[i], soundname, sizeof(soundname)))
        {
            continue;
        }
        // FileExists is relative to root gamedir, but sound functions
        // auto-append the "sound" folder, so use a placeholder variable
        // here to confirm the file exists.
        Format(filebuff, sizeof(filebuff), "sound/%s", soundname);
        if (!FileExists(filebuff))
        {
            SetFailState("Reload sound doesn't exist on server disk: \"%s\"", filebuff);
        }
        Format(filebuff, sizeof(filebuff), "%s%s", SOUND_CHARACTERS, soundname);
        if (!PrecacheSound(soundname))
        {
            SetFailState("Failed to precache sound: \"%s\"", soundname);
        }
    }
}

public void OnEntityCreated(int entity)
{
    if (!IsValidEdict(entity))
    {
        return;
    }
    char classname[NEO_MAX_WEPNAME_STRLEN + 1];
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

// For a given Neotokyo weapon classname, pass the corresponding reload sound by reference.
// Return boolean of whether an emittable reload sound was found for the weapon.
// This returns false for the supa7, because its shell reload is already world-audible.
bool GetReloadSoundOfWeapon(const char[] weapon_classname, char[] out_sound, const int out_sound_maxlen)
{
    int i;
    for (i = 0; i < sizeof(weapons_primary); ++i)
    {
        if (StrEqual(weapon_classname, weapons_primary[i]))
        {
            return (
                strlen(g_sReloadSounds_Primary[i]) > 0 &&
                strcopy(
                    out_sound,
                    out_sound_maxlen,
                    g_sReloadSounds_Primary[i]
                ) > 0
            );
        }
    }

    for (i = 0; i < sizeof(weapons_secondary); ++i)
    {
        if (StrEqual(weapon_classname, weapons_secondary[i]))
        {
            return (
                strlen(g_sReloadSounds_Secondary[i]) > 0 &&
                strcopy(
                    out_sound,
                    out_sound_maxlen,
                    g_sReloadSounds_Secondary[i]
                ) > 0
            );
        }
    }

    return false;
}

// For a given int array arr of size num_values, pass by refence to array
// out_arr all of its values in range (0, num_values) that are not equal to
// unique_value_to_filter.
// Assumes out_arr will be able to contain at least num_values-(num filtered)
// amount of values.
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

int FilterByDistance(float distance_sqr, const int[] client_arr, int num_values, const float pos[3],
    int[] out_arr)
{
    int num_out = 0;
    float client_pos[3];
    for (int i = 0; i < num_values; ++i)
    {
        GetClientAbsOrigin(client_arr[i], client_pos);
        if (GetVectorDistance(client_pos, pos, true) <= distance_sqr)
        {
            out_arr[num_out++] = client_arr[i];
        }
    }
    return num_out;
}

// Detour of the weapon reload.
// The post-hook value of hReloadSuccessful returns true if the reload is successful
// (ie. has enough ammo, is allowed to reload...).
// Note: if you need to debug this with print statements, the print to chat sound channel
// triggering at the exact same time can actually cut off the sound effect;
// PrintToServer may be more useful inside this detour with regard to audio debug.
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

    char classname[NEO_MAX_WEPNAME_STRLEN + 1];
    if (!GetEdictClassname(edict, classname, sizeof(classname)))
    {
        return MRES_Ignored;
    }

    char audio_sample[PLATFORM_MAX_PATH];
    // Can happen if trying to reload something like the knife
    if (!GetReloadSoundOfWeapon(classname, audio_sample, sizeof(audio_sample)))
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
    // TODO: what is the non-audible placeholder value, -1?
    // this extra alloc could probably be refactored out using the appropriate placeholders.
    int[] audience_sans_owner = new int[num_audience - 1];
    // Filter the gun owner, because they'll already hear their own reload
    num_audience = FilterUniqueValueFromArray(audience, num_audience, owner, audience_sans_owner);

    if (num_audience == 0)
    {
        return MRES_Ignored;
    }

    // The audible distance algorithm sucks so roll our own
    num_audience = FilterByDistance(
        // Squared, because compared against squared Euclidean dist for perf
        MAX_AUDIBLE_DISTANCE * MAX_AUDIBLE_DISTANCE,
        audience_sans_owner,
        num_audience,
        pos,
        audience_sans_owner
    );

    if (num_audience == 0)
    {
        return MRES_Ignored;
    }

    EmitSound(
        audience_sans_owner,
        num_audience,
        audio_sample,
        owner,
        // Need to set streaming type channel to avoid stepping over existing sounds
        SNDCHAN_STATIC,
        SNDLEVEL_RELOAD,
        _,
        _,
        _,
        _,
        // Already specifying to emit from owner, but passing the actual coordinates
        // in since we already have them available here anyway.
        pos
    );

    return MRES_Ignored;
}
