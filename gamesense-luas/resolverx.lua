--[[ 
resolver lua for gamesense :3
this is more of testing rather than an actual resolver
let the messy code nightmare begin!

Layer Index's

[0]  Movement Stop Direction
     - Reports direction when stopping:
       left (0.25), right (0.75), back (0.5)

[1]  Crouch Fade
     - 1.0 when standing
     - 0.0 when crouching

[2] View Yaw Modifier / Torso Yaw Delta
    - Normalized yaw offset from LBY (0.0–1.0)
    - 0.000 = full left, 0.500 = right, 0.750 = front
    - Loops around with view rotation

[3]  Running/Walking State
     - 1.0 when moving
     - 0.0 when idle

[4]  Unused
     - Always 0.0 in your testing

[5]  Unused
     - Always 0.0 in your testing

[6] Air/Fall Animation
     - Active when jumping or falling
     - PlaybackRate & Weight spike when air animation plays
     - Tied to m_fFlags & ~FL_ONGROUND

[7]  Strafe Direction
     - 1.0, 0.75, or 0.25 depending on side movement

[8]  Crouch State
     - 1.0 when crouching
     - 0.0 when standing

[9]  Movement/Crouch Blend?
     - 1.0 idle
     - Drops to 0.0 when crouch or running

[10] Run/Move Indicator
     - 0.0 idle
     - 1.0 when running

[11] Lower Body Yaw (LBY)
     - 0.500 is neutral
     - ~0.0213 (−180 degrees) (-60)
     - ~0.9787 (+180 degrees) (60)

[12] Pitch
     - 0.5 neutral
     - ~0.0061 (0) when looking up
     - ~0.9939 (1) when looking down
]]



local ffi = require 'ffi'
local crr_t = ffi.typeof('void*(__thiscall*)(void*)')
local cr_t = ffi.typeof('void*(__thiscall*)(void*)')
local gm_t = ffi.typeof('const void*(__thiscall*)(void*)')
local gsa_t = ffi.typeof('int(__fastcall*)(void*, void*, int)')
ffi.cdef[[
    struct animation_layer_t
    {
        char pad20[24];
        uint32_t m_nSequence;
        float m_flPrevCycle;
        float m_flWeight;
        float m_flWeightDeltaRate;
        float m_flPlaybackRate;
        float m_flCycle;
        uintptr_t m_pOwner;
        char pad_0038[ 4 ];
    };
    struct c_animstate {
        char pad[ 3 ];
        char m_bForceWeaponUpdate; //0x4
        char pad1[ 91 ];
        void* m_pBaseEntity; //0x60
        void* m_pActiveWeapon; //0x64
        void* m_pLastActiveWeapon; //0x68
        float m_flLastClientSideAnimationUpdateTime; //0x6C
        int m_iLastClientSideAnimationUpdateFramecount; //0x70
        float m_flAnimUpdateDelta; //0x74
        float m_flEyeYaw; //0x78
        float m_flPitch; //0x7C
        float m_flGoalFeetYaw; //0x80
        float m_flCurrentFeetYaw; //0x84
        float m_flCurrentTorsoYaw; //0x88
        float m_flUnknownVelocityLean; //0x8C
        float m_flLeanAmount; //0x90
        char pad2[ 4 ];
        float m_flFeetCycle; //0x98
        float m_flFeetYawRate; //0x9C
        char pad3[ 4 ];
        float m_fDuckAmount; //0xA4
        float m_fLandingDuckAdditiveSomething; //0xA8
        char pad4[ 4 ];
        float m_vOriginX; //0xB0
        float m_vOriginY; //0xB4
        float m_vOriginZ; //0xB8
        float m_vLastOriginX; //0xBC
        float m_vLastOriginY; //0xC0
        float m_vLastOriginZ; //0xC4
        float m_vVelocityX; //0xC8
        float m_vVelocityY; //0xCC
        char pad5[ 4 ];
        float m_flUnknownFloat1; //0xD4
        char pad6[ 8 ];
        float m_flUnknownFloat2; //0xE0
        float m_flUnknownFloat3; //0xE4
        float m_flUnknown; //0xE8
        float m_flSpeed2D; //0xEC
        float m_flUpVelocity; //0xF0
        float m_flSpeedNormalized; //0xF4
        float m_flFeetSpeedForwardsOrSideWays; //0xF8
        float m_flFeetSpeedUnknownForwardOrSideways; //0xFC
        float m_flTimeSinceStartedMoving; //0x100
        float m_flTimeSinceStoppedMoving; //0x104
        bool m_bOnGround; //0x108
        bool m_bInHitGroundAnimation; //0x109
        float m_flTimeSinceInAir; //0x10A
        float m_flLastOriginZ; //0x10E
        float m_flHeadHeightOrOffsetFromHittingGroundAnimation; //0x112
        float m_flStopToFullRunningFraction; //0x116
        char pad7[ 4 ]; //0x11A
        float m_flMagicFraction; //0x11E
        char pad8[ 60 ]; //0x122
        float m_flWorldForce; //0x15E
        char pad9[ 462 ]; //0x162
        float m_flMaxYaw; //0x334
    };
]]

-- Constants (I know, this is awful.)
local MAX_PLAYERS = 64
local MAX_ANIMATION_LAYERS = 13
local DESYNC_INCREMENT = 10
local MAX_DESYNC_VALUE = 60
local MIN_DESYNC_VALUE = -60
local RESOLVER_UPDATE_INTERVAL = 0.04
local RESET_THRESHOLD = 2

-- FFI setup
local classptr = ffi.typeof('void***')
local rawientitylist = client.create_interface('client_panorama.dll', 'VClientEntityList003') or error('VClientEntityList003 wasnt found', 2)
local ientitylist = ffi.cast(classptr, rawientitylist) or error('rawientitylist is nil', 2)
local get_client_networkable = ffi.cast('void*(__thiscall*)(void*, int)', ientitylist[0][0]) or error('get_client_networkable_t is nil', 2)
local get_client_entity = ffi.cast('void*(__thiscall*)(void*, int)', ientitylist[0][3]) or error('get_client_entity is nil', 2)

local rawivmodelinfo = client.create_interface('engine.dll', 'VModelInfoClient004')
local ivmodelinfo = ffi.cast(classptr, rawivmodelinfo) or error('rawivmodelinfo is nil', 2)
local get_studio_model = ffi.cast('void*(__thiscall*)(void*, const void*)', ivmodelinfo[0][32])

local seq_activity_sig = client.find_signature('client_panorama.dll','\x55\x8B\xEC\x53\x8B\x5D\x08\x56\x8B\xF1\x83')

-- Helper functions
local function get_model(b)
    if b then
        b = ffi.cast(classptr, b)
        local c = ffi.cast(crr_t, b[0][0])
        local d = c(b) or error('error getting client unknown', 2)
        if d then
            d = ffi.cast(classptr, d)
            local e = ffi.cast(cr_t, d[0][5])(d) or error('error getting client renderable', 2)
            if e then
                e = ffi.cast(classptr, e)
                return ffi.cast(gm_t, e[0][8])(e) or error('error getting model_t', 2)
            end
        end
    end
end

local function get_sequence_activity(b, c, d)
    b = ffi.cast(classptr, b)
    local e = get_studio_model(ivmodelinfo, get_model(c))
    if e == nil then
        return -1
    end
    local f = ffi.cast(gsa_t, seq_activity_sig)
    return f(b, e, d)
end

local function get_anim_layer(b, c)
    c = c or 1
    b = ffi.cast(classptr, b)
    return ffi.cast('struct animation_layer_t**', ffi.cast('char*', b) + 0x2990)[0][c]
end

-- Math tools
local Tools = {
    Clamp = function(n, mn, mx)
        return math.max(math.min(n, mx), mn)
    end,

    YawTo360 = function(yaw)
        return yaw < 0 and 360 + yaw or yaw
    end,

    YawTo180 = function(yaw)
        return yaw > 180 and yaw - 360 or yaw
    end,

    YawNormalizer = function(yaw)
        if yaw > 360 then
            return yaw - 360
        elseif yaw < 0 then
            return 360 + yaw
        end
        return yaw
    end,

    CalculateHitRate = function(hits, shots)
        if shots == 0 then return 0 end
        return hits / shots
    end,

	Round = function(n)
		return n >= 0 and math.floor(n + 0.5) or math.ceil(n - 0.5)
	end

}

-- UI elements
local MenuV = {
    ["Anti-Aim Correction"] = ui.reference("Rage", "Other", "Anti-Aim Correction"),
    ["ResetAll"] = ui.reference("Players", "Players", "Reset All"),
    ["ForceBodyYaw"] = ui.reference("Players", "Adjustments", "Force Body Yaw"),
    ["CorrectionActive"] = ui.reference("Players", "Adjustments", "Correction Active")
}

local MenuC = {
    ["resolver"] = ui.new_checkbox("Rage", "Other", "enable resolver"),
    ["debug logs"] = ui.new_checkbox("Rage", "Other", "debug logs"),
    ["movement adjustment"] = ui.new_checkbox("Rage", "Other", "movement adjustment"),
    ["debug visuals"] = ui.new_checkbox("Rage", "Other", "visualize debugs"),
    ["AutomaticAdjustment"] = ui.new_checkbox("Rage", "Other", "Automatic Adjustment"),
}

-- Data structures
local PlayerData = {}
local LastUpdateTime = 0

-- Initialize player data table
local function InitializePlayerData()
    for i = 1, MAX_PLAYERS do
        PlayerData[i] = {
            SideCount = 0,
            Side = "Left",
            Desync = 0,
            ShotsFired = 0,
            ShotsHit = 0,
            ShotsMissed = 0,
            ResolvedStatus = false,
            LastKnownState = {},
            SuccessfulValues = {},
            AnimLayers = {},
            UpdateTime = 0,
            FailedAttempts = 0,
            LastHitYawValue = nil,
            HistoricalDesyncs = {}
        }
    end
end

-- Reset player data
local function ResetPlayerData(player)
    if not PlayerData[player] then return end
    PlayerData[player].SideCount = 0
    PlayerData[player].Side = "Left"
    PlayerData[player].Desync = 0
    PlayerData[player].ShotsFired = 0
    PlayerData[player].ShotsHit = 0
    PlayerData[player].ShotsMissed = 0
    PlayerData[player].ResolvedStatus = false
    PlayerData[player].LastKnownState = {}
    PlayerData[player].SuccessfulValues = {}
    PlayerData[player].AnimLayers = {}
    PlayerData[player].UpdateTime = 0
    PlayerData[player].FailedAttempts = 0
    PlayerData[player].LastHitYawValue = nil
    PlayerData[player].HistoricalDesyncs = {}
end

local function ResetAllPlayerData()
    for i = 1, MAX_PLAYERS do
        ResetPlayerData(i)
    end
end

-- UI update
local function UpdateUIVisibility()
    local enabled = ui.get(MenuC["resolver"])
    ui.set_visible(MenuC["debug logs"], enabled)
    ui.set_visible(MenuC["movement adjustment"], enabled)
    ui.set_visible(MenuC["debug visuals"], enabled)
    ui.set_visible(MenuC["AutomaticAdjustment"], enabled)
    ui.set_visible(MenuV["CorrectionActive"], not enabled)

    if enabled then
        ui.set(MenuV["ResetAll"], true)
    end
end

-- Movement state detection
local function GetMovementState(player)
    local vx, vy, vz = entity.get_prop(player, "m_vecVelocity")
    local speed = math.sqrt((vx or 0)^2 + (vy or 0)^2 + (vz or 0)^2)
    local flags = entity.get_prop(player, "m_fFlags") or 0
    local in_air = bit.band(flags, 1) == 0

    return {
        Speed = speed,
        InAir = in_air,
        OnGround = bit.band(flags, 1) ~= 0,
        Ducking = bit.band(flags, 2) ~= 0
    }
end

-- animation layer analysis
local function AnalyzeAnimLayers(player, playerEntity)
    local result = {
        Desync = 0,
        Side = "Left",
        DesyncDetected = false,
        SideCount = 0
    }

    local animLayers = {}

    -- extract animation layers
    for i = 1, MAX_ANIMATION_LAYERS do
        local animLayer = get_anim_layer(playerEntity, i)
        if not animLayer then goto continue end

        animLayers[i] = {
            PrevCycle = animLayer.m_flPrevCycle,
            Weight = animLayer.m_flWeight,
            WeightDeltaRate = animLayer.m_flWeightDeltaRate,
            PlaybackRate = animLayer.m_flPlaybackRate,
            Cycle = animLayer.m_flCycle
        }

        ::continue::
    end

    -- layer 11 is Lower Body Yaw (LBY)
    local layer11 = animLayers[11]
    if not layer11 then return result end

    -- extract decimal digits of layer11 fields for fine analysis
    local digits = {}
    for field, value in pairs(layer11) do
        digits[field] = {}
        for d = 1, 10 do
            digits[field][d] = math.floor(value * (10^d)) - (math.floor(value * (10^(d - 1))) * 10)
        end
    end

    -- desync detection using PlaybackRate digits
    local sumSideR = digits.PlaybackRate[4] + digits.PlaybackRate[5] + digits.PlaybackRate[6] + digits.PlaybackRate[7]
    local sumSideS = digits.PlaybackRate[6] + digits.PlaybackRate[7] + digits.PlaybackRate[8] + digits.PlaybackRate[9]

    if digits.PlaybackRate[3] == 0 then
        result.DesyncDetected = true
        result.Desync = -3.4117 * sumSideS + 98.9393
    else
        result.DesyncDetected = true
        result.Desync = -3.4117 * sumSideR + 98.9393
    end

    -- clamp desync within valid bounds
    result.Desync = Tools.Clamp(result.Desync, MIN_DESYNC_VALUE, MAX_DESYNC_VALUE)

    -- side detection based on weight decimal digits from layer11
    local temp45 = tonumber(digits.Weight[4] .. digits.Weight[5]) or 0

    if digits.Weight[2] == 0 then
        if (layer11.Weight * 10^5 > 300) then
            result.SideCount = 1
        else
            result.SideCount = 0
        end
    elseif digits.Weight[1] == 9 then
        if temp45 == 29 then
            result.Side = "Left"
        elseif temp45 == 30 then
            result.Side = "Right"
        elseif digits.Weight[2] == 9 then
            result.SideCount = 2
        else
            result.SideCount = 0
        end
    end

    return result
end


-- adaptive learning function
local function UpdateHistoricalData(playerData, desyncValue)
    if not playerData.HistoricalDesyncs then
        playerData.HistoricalDesyncs = {}
    end

    table.insert(playerData.HistoricalDesyncs, desyncValue)

    -- keep only the last 3 entries
    if #playerData.HistoricalDesyncs > 3 then
        table.remove(playerData.HistoricalDesyncs, 1)
    end

    -- calculate average desync
    local sum = 0
    for _, v in ipairs(playerData.HistoricalDesyncs) do
        sum = sum + v
    end

    return sum / #playerData.HistoricalDesyncs
end

local function AdaptiveLearning(playerData)
    if not playerData.HistoricalDesyncs or #playerData.HistoricalDesyncs < 2 then
        return playerData.Desync
    end

    -- simple moving average to smooth desync values
    local avgDesync = UpdateHistoricalData(playerData, playerData.Desync)

    -- adjust desync based on historical data
    if math.abs(playerData.Desync - avgDesync) > 5 then
        playerData.Desync = avgDesync
    end

    return playerData.Desync
end

-- debug visualization
local function DrawDebugInfo(player)
    if not ui.get(MenuC["debug visuals"]) then return end
    if not entity.is_alive(player) then return end

    -- ignore yourself and teammates
    local local_player = entity.get_local_player()
    if player == local_player then return end

    local local_team = entity.get_prop(local_player, "m_iTeamNum")
    local player_team = entity.get_prop(player, "m_iTeamNum")
    if local_team == player_team then return end

    local x, y, z = entity.get_prop(player, "m_vecOrigin")
    if not x or not y or not z then return end

    local screen_x, screen_y = renderer.world_to_screen(x, y, z + 100)
    if not screen_x or not screen_y then return end -- prevents flickering due to invalid coordinates

    local playerData = PlayerData[player]
    if not playerData then return end

    -- round desync value
    local roundedDesync = Tools.Round(playerData.Desync)

    -- base info
    renderer.text(screen_x, screen_y - 60, 255, 255, 255, 255, "c", 0, "Player " .. player)

    -- desync info
    local desyncColor = playerData.ResolvedStatus and {0, 255, 0, 255} or {255, 0, 0, 255}
    renderer.text(screen_x, screen_y - 45, desyncColor[1], desyncColor[2], desyncColor[3], desyncColor[4], "c", 0,
                  "Desync: " .. roundedDesync .. "° | " .. playerData.Side)

    -- movement state
    local movementState = GetMovementState(player)
    local movementText = string.format("Speed: %.1f | %s", movementState.Speed, movementState.InAir and "Air" or "Ground")
    renderer.text(screen_x, screen_y - 30, 255, 255, 255, 255, "c", 0, movementText)

    -- shot stats
    local hitRate = Tools.CalculateHitRate(playerData.ShotsHit, playerData.ShotsFired)
    local hitRateColor = hitRate > 0.7 and {0, 255, 0, 255} or hitRate > 0.4 and {255, 255, 0, 255} or {255, 0, 0, 255}

    renderer.text(screen_x, screen_y - 15, 255, 255, 255, 255, "c", 0,
                  "Shots: " .. playerData.ShotsFired .. " | Hits: " .. playerData.ShotsHit)

    renderer.text(screen_x, screen_y + 0, hitRateColor[1], hitRateColor[2], hitRateColor[3], hitRateColor[4], "c", 0,
                  "Hit Rate: " .. string.format("%.0f%%", hitRate * 100))

    -- resolver state
    local statusText = playerData.ResolvedStatus and "RESOLVED" or "RESOLVING"
    local statusColor = playerData.ResolvedStatus and {0, 255, 0, 255} or {255, 165, 0, 255}

    renderer.text(screen_x, screen_y + 15, statusColor[1], statusColor[2], statusColor[3], statusColor[4], "c", 0, statusText)

    -- additional debug info
    if playerData.LastHitYawValue then
        renderer.text(screen_x, screen_y + 30, 255, 255, 0, 255, "c", 0,
                      "last hit yaw: " .. Tools.Round(playerData.LastHitYawValue))
    end

    if playerData.HistoricalDesyncs and #playerData.HistoricalDesyncs > 0 then
        local avgDesync = 0
        for _, v in ipairs(playerData.HistoricalDesyncs) do
            avgDesync = avgDesync + v
        end
        avgDesync = avgDesync / #playerData.HistoricalDesyncs

        renderer.text(screen_x, screen_y + 45, 0, 255, 255, 255, "c", 0,
                      "avg desync: " .. Tools.Round(avgDesync))
    end
end


local function ApplyResolver()
    if not ui.get(MenuC["resolver"]) then return end

    local currentTime = globals.realtime()
    if currentTime - LastUpdateTime < RESOLVER_UPDATE_INTERVAL then return end
    LastUpdateTime = currentTime

    local players = entity.get_players(true)
    if not players then return end

    for i, player in pairs(players) do
        if not entity.is_alive(player) then goto continue end

        local playerEntity = get_client_entity(ientitylist, player)
        if not playerEntity then goto continue end

        local playerData = PlayerData[player]
        if not playerData then goto continue end

        -- Get movement state
        local movementState = GetMovementState(player)

        -- Basic analysis of animation layers
        local analysis = AnalyzeAnimLayers(player, playerEntity)

        -- Update side counter
        playerData.SideCount = playerData.SideCount + (analysis.SideCount or 0)

        -- Check if side needs to be flipped
        if playerData.SideCount >= RESET_THRESHOLD then
            playerData.Side = playerData.Side == "Left" and "Right" or "Left"
            playerData.SideCount = 0
        else
            -- Use detected side if available
            if analysis.Side then
                playerData.Side = analysis.Side
            end
        end

        -- Update desync value if detected
        if analysis.DesyncDetected then
            playerData.Desync = analysis.Desync
        end

        -- movement adjustment
        if ui.get(MenuC["movement adjustment"]) then
            -- Adjust desync based on movement state
            if movementState.Speed > 100 then
                -- Moving players often have lower desync values
                playerData.Desync = Tools.Clamp(playerData.Desync - 5, MIN_DESYNC_VALUE, MAX_DESYNC_VALUE)
            end

            if movementState.InAir then
                -- In-air players often have restricted desync
                playerData.Desync = Tools.Clamp(playerData.Desync - 10, MIN_DESYNC_VALUE, MAX_DESYNC_VALUE)
            end

        end

        -- apply adaptive learning
        if playerData.HistoricalDesyncs then
            playerData.Desync = AdaptiveLearning(playerData)
        end

        -- use the last hit yaw value if a shot has landed
        if playerData.LastHitYawValue then
            playerData.Desync = playerData.LastHitYawValue
        end

        -- set force body yaw in plist
        plist.set(player, "Force Body Yaw", true)

        -- apply body yaw correction
        if playerData.Side == "Right" then
            plist.set(player, "force body yaw value", playerData.Desync)
        else
            plist.set(player, "force body yaw value", -playerData.Desync)
        end

        -- draw debug info
        DrawDebugInfo(player)

        ::continue::
    end
end

-- event callbacks
local function RegisterEventCallbacks()
    client.set_event_callback("aim_fire", function(e)
        local target = e.target
        if not PlayerData[target] then return end
        PlayerData[target].ShotsFired = PlayerData[target].ShotsFired + 1

        -- store current state when firing
        PlayerData[target].LastKnownState = {
            Side = PlayerData[target].Side,
            Desync = PlayerData[target].Desync
        }
    end)

    client.set_event_callback("aim_hit", function(e)
        local target = e.target
        if not PlayerData[target] then return end
        PlayerData[target].ShotsHit = PlayerData[target].ShotsHit + 1
        PlayerData[target].LastHitYawValue = PlayerData[target].Desync
        PlayerData[target].ResolvedStatus = true

        table.insert(PlayerData[target].SuccessfulValues, {
            Side = PlayerData[target].LastKnownState.Side,
            Desync = PlayerData[target].LastKnownState.Desync
        })

        if ui.get(MenuC["debug logs"]) then
            client.log("Resolver: Hit player " .. target .. " at " .. PlayerData[target].Desync .. "° side=" .. PlayerData[target].Side)
        end
    end)

    client.set_event_callback("aim_miss", function(e)
        local target = e.target
        if not PlayerData[target] then return end
        local pdata = PlayerData[target]

        pdata.ShotsMissed = pdata.ShotsMissed + 1
        pdata.LastHitYawValue = nil
        pdata.ResolvedStatus = false

        if ui.get(MenuC["movement adjustment"]) then
            pdata.FailedAttempts = pdata.FailedAttempts + 1

            if pdata.FailedAttempts >= 2 then
                pdata.Side = pdata.Side == "Left" and "Right" or "Left"
                pdata.FailedAttempts = 0

                if ui.get(MenuC["debug logs"]) then
                    client.log("Resolver: Flipped side for player " .. target .. " to " .. pdata.Side .. " (desync=" .. pdata.Desync .. "°) after consecutive misses")
                end
            end

            local adjustment = 5 + (pdata.ShotsMissed % 3) * 5
            pdata.Desync = Tools.Clamp(pdata.Desync + adjustment, MIN_DESYNC_VALUE, MAX_DESYNC_VALUE)

            if ui.get(MenuC["debug logs"]) then
                client.log("Resolver: missed shot, applying desync for player " .. target .. " to " .. pdata.Desync .. "°")
            end
        end
    end)


    client.set_event_callback("round_start", function()
        ResetAllPlayerData()
    end)

    client.set_event_callback("round_end", function()
        ResetAllPlayerData()
    end)
end

-- Initialize
InitializePlayerData()
UpdateUIVisibility()
RegisterEventCallbacks()

-- ensure DrawDebugInfo runs in the paint event to avoid flickering
client.set_event_callback("paint", function()
    ApplyResolver()
    for _, player in ipairs(entity.get_players()) do
        DrawDebugInfo(player)
    end
end)


-- UI callbacks
ui.set_callback(MenuC["resolver"], UpdateUIVisibility)