local weapons = {
    'WEAPON_KNIFE',
    'WEAPON_NIGHTSTICK',
    'WEAPON_BREAD',
    'WEAPON_FLASHLIGHT',
    'WEAPON_HAMMER',
    'WEAPON_BAT',
    'WEAPON_GOLFCLUB',
    'WEAPON_CROWBAR',
    'WEAPON_BOTTLE',
    'WEAPON_DAGGER',
    'WEAPON_HATCHET',
    'WEAPON_MACHETE',
    'WEAPON_SWITCHBLADE',
    'WEAPON_BATTLEAXE',
    'WEAPON_POOLCUE',
    'WEAPON_WRENCH',
    'WEAPON_PISTOL',
    'WEAPON_PISTOL_MK2',
    'WEAPON_COMBATPISTOL',
    'WEAPON_APPISTOL',
    'WEAPON_PISTOL50',
    'WEAPON_REVOLVER',
    'WEAPON_SNSPISTOL',
    'WEAPON_HEAVYPISTOL',
    'WEAPON_VINTAGEPISTOL',
    'WEAPON_MICROSMG',
    'WEAPON_SMG',
    'WEAPON_ASSAULTSMG',
    'WEAPON_MINISMG',
    'WEAPON_MACHINEPISTOL',
    'WEAPON_COMBATPDW',
    'WEAPON_PUMPSHOTGUN',
    'WEAPON_SAWNOFFSHOTGUN',
    'WEAPON_ASSAULTSHOTGUN',
    'WEAPON_BULLPUPSHOTGUN',
    'WEAPON_HEAVYSHOTGUN',
    'WEAPON_ASSAULTRIFLE',
    'WEAPON_CARBINERIFLE',
    'WEAPON_ADVANCEDRIFLE',
    'WEAPON_SPECIALCARBINE',
    'WEAPON_BULLPUPRIFLE',
    'WEAPON_COMPACTRIFLE',
    'WEAPON_MG',
    'WEAPON_COMBATMG',
    'WEAPON_GUSENBERG',
    'WEAPON_SNIPERRIFLE',
    'WEAPON_HEAVYSNIPER',
    'WEAPON_MARKSMANRIFLE',
    'WEAPON_GRENADELAUNCHER',
    'WEAPON_RPG',
    'WEAPON_STINGER',
    'WEAPON_MINIGUN',
    'WEAPON_GRENADE',
    'WEAPON_STICKYBOMB',
    'WEAPON_SMOKEGRENADE',
    'WEAPON_BZGAS',
    'WEAPON_MOLOTOV',
    'WEAPON_DIGISCANNER',
    'WEAPON_FIREWORK',
    'WEAPON_MUSKET',
    'WEAPON_STUNGUN',
    'WEAPON_HOMINGLAUNCHER',
    'WEAPON_PROXMINE',
    'WEAPON_FLAREGUN',
    'WEAPON_MARKSMANPISTOL',
    'WEAPON_RAILGUN',
    'WEAPON_DBSHOTGUN',
    'WEAPON_AUTOSHOTGUN',
    'WEAPON_COMPACTLAUNCHER',
    'WEAPON_PIPEBOMB',
    'WEAPON_DOUBLEACTION',
    'WEAPON_SNOWBALL',
    'WEAPON_PISTOLXM3',
    'WEAPON_CANDYCANE',
    'WEAPON_CERAMICPISTOL',
    'WEAPON_NAVYREVOLVER',
    'WEAPON_GADGETPISTOL',
    'WEAPON_PISTOLXM3',
    'WEAPON_TECPISTOL',
    'WEAPON_HEAVYRIFLE',
    'WEAPON_MILITARYRIFLE',
    'WEAPON_TACTICALRIFLE',
    'WEAPON_SWEEPERSHOTGUN',
    'WEAPON_ASSAULTRIFLE_MK2',
    'WEAPON_BULLPUPRIFLE_MK2',
    'WEAPON_CARBINERIFLE_MK2',
    'WEAPON_COMBATMG_MK2',
    'WEAPON_HEAVYSNIPER_MK2',
    'WEAPON_KNUCKLE',
    'WEAPON_MARKSMANRIFLE_MK2',
    'WEAPON_PRECISIONRIFLE',
    'WEAPON_PETROLCAN',
    'WEAPON_PUMPSHOTGUN_MK2',
    'WEAPON_RAYCARBINE',
    'WEAPON_RAYMINIGUN',
    'WEAPON_RAYPISTOL',
    'WEAPON_REVOLVER_MK2',
    'WEAPON_SMG_MK2',
    'WEAPON_SNSPISTOL_MK2',
    'WEAPON_SPECIALCARBINE_MK2',
    'WEAPON_STONE_HATCHET'
}

local holstered = true
local canFire = true
local currWeap = `WEAPON_UNARMED`
local currHolster = nil
local currHolsterTexture = nil
local wearingHolster = nil

local function loadAnimDict(dict)
    if HasAnimDictLoaded(dict) then return end
    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do
        Wait(10)
    end
end

local function checkWeapon(newWeap)
    for i = 1, #weapons do
        if joaat(weapons[i]) == newWeap then
            return true
        end
    end
    return false
end

local function isWeaponHolsterable(weap)
    for i = 1, #Config.WeapDraw.weapons do
        if joaat(Config.WeapDraw.weapons[i]) == weap then
            return true
        end
    end
    return false
end

RegisterNetEvent('tmg-weapons:ResetHolster', function()
    holstered = true
    canFire = true
    currWeap = `WEAPON_UNARMED`
    currHolster = nil
    currHolsterTexture = nil
    wearingHolster = nil
end)


local isAnimating = false

RegisterNetEvent('tmg-weapons:client:DrawWeapon', function(targetWeaponName)
    if GetResourceState('tmg-inventory') == 'missing' then return end
    if isAnimating then return end 
    
    local ped = PlayerPedId()
    
    local newWeap = targetWeaponName and joaat(targetWeaponName) or `WEAPON_UNARMED`
    
    if IsEntityDead(ped) or IsPedFalling(ped) or IsPedInParachuteFreeFall(ped) then 
        SetCurrentPedWeapon(ped, newWeap, true)
        return 
    end

    isAnimating = true 

    local pos = GetEntityCoords(ped, true)
    local rot = GetEntityHeading(ped)
    
    local animDicts = {
        'reaction@intimidation@1h',
        'reaction@intimidation@cop@unarmed',
        'rcmjosh4',
        'weapons@pistol@'
    }
    for i = 1, #animDicts do loadAnimDict(animDicts[i]) end

    local holsterVariant = GetPedDrawableVariation(ped, 8)
    local wearingHolster = false
    for i = 1, #Config.WeapDraw.variants do
        if holsterVariant == Config.WeapDraw.variants[i] then
            wearingHolster = true
            break 
        end
    end

    CreateThread(function()
        if newWeap ~= `WEAPON_UNARMED` and checkWeapon(newWeap) then
            if holstered then
                if wearingHolster then
                    canFire = false
                    CeaseFire() 
                    
                    currHolster = GetPedDrawableVariation(ped, 7)
                    currHolsterTexture = GetPedTextureVariation(ped, 7)
                    
                    TaskPlayAnimAdvanced(ped, 'rcmjosh4', 'josh_leadout_cop2', pos.x, pos.y, pos.z, 0, 0, rot, 3.0, 3.0, -1, 50, 0, 0, 0)
                    Wait(300)
                    
                    SetCurrentPedWeapon(ped, newWeap, true)
                    
                    if isWeaponHolsterable(newWeap) then
                        SetPedComponentVariation(ped, 7, currHolster == 8 and 2 or currHolster == 1 and 3 or currHolster == 6 and 5, currHolsterTexture, 2)
                    end
                    
                    currWeap = newWeap
                    Wait(300)
                    ClearPedTasks(ped)
                    holstered = false
                    canFire = true
                else
                    canFire = false
                    CeaseFire()
                    TaskPlayAnimAdvanced(ped, 'reaction@intimidation@1h', 'intro', pos.x, pos.y, pos.z, 0, 0, rot, 8.0, 3.0, -1, 50, 0, 0, 0)
                    Wait(1000)
                    SetCurrentPedWeapon(ped, newWeap, true)
                    currWeap = newWeap
                    Wait(1400)
                    ClearPedTasks(ped)
                    holstered = false
                    canFire = true
                end
            end

        else
            if not holstered and checkWeapon(currWeap) then
                if wearingHolster then
                    canFire = false
                    CeaseFire()
                    TaskPlayAnimAdvanced(ped, 'reaction@intimidation@cop@unarmed', 'intro', pos.x, pos.y, pos.z, 0, 0, rot, 3.0, 3.0, -1, 50, 0, 0, 0)
                    Wait(500)

                    if isWeaponHolsterable(currWeap) then
                        SetPedComponentVariation(ped, 7, currHolster, currHolsterTexture, 2)
                    end

                    SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
                    ClearPedTasks(ped)
                    holstered = true
                    canFire = true
                    currWeap = `WEAPON_UNARMED`
                else
                    canFire = false
                    CeaseFire()
                    TaskPlayAnimAdvanced(ped, 'reaction@intimidation@1h', 'outro', pos.x, pos.y, pos.z, 0, 0, rot, 8.0, 3.0, -1, 50, 0, 0, 0)
                    Wait(1400)
                    SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
                    ClearPedTasks(ped)
                    holstered = true
                    canFire = true
                    currWeap = `WEAPON_UNARMED`
                end
            end
        end

        isAnimating = false 
    end)
end)

function CeaseFire()
    CreateThread(function()
        if GetResourceState('tmg-inventory') == 'missing' then return end
        while not canFire do
            DisableControlAction(0, 25, true)
            DisablePlayerFiring(PlayerId(), true)
            Wait(0)
        end
    end)
end
