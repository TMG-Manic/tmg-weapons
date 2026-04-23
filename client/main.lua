
local TMGCore = exports['tmg-core']:GetCoreObject()
local PlayerData = TMGCore.Functions.GetPlayerData()
local CurrentWeaponData, CanShoot, MultiplierAmount, currentWeapon = {}, true, 0, nil



local currentRepairPoint = nil

CreateThread(function()
    while true do
        local sleep = 500
        if LocalPlayer.state.isLoggedIn then
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            local found = false

            for k, data in pairs(Config.WeaponRepairPoints) do
                local dist = #(pos - data.coords)
                if dist < 10.0 then
                    sleep = 0 
                    found = true
                    currentRepairPoint = k
                    
                    if dist < 1.5 then
                        HandleRepairInteraction(k, data)
                    end
                    break 
                end
            end
            
            if not found then 
                currentRepairPoint = nil 
            end
        end
        Wait(sleep)
    end
end)

function HandleRepairInteraction(key, data)
    local citizenid = TMGCore.Functions.GetPlayerData().citizenid
    
    if data.IsRepairing then
        if data.RepairingData.CitizenId ~= citizenid then
            DrawText3Ds(data.coords.x, data.coords.y, data.coords.z, Lang:t('info.repairshop_not_usable'))
        elseif not data.RepairingData.Ready then
            DrawText3Ds(data.coords.x, data.coords.y, data.coords.z, Lang:t('info.weapon_will_repair'))
        else
            DrawText3Ds(data.coords.x, data.coords.y, data.coords.z, Lang:t('info.take_weapon_back'))
            if IsControlJustPressed(0, 38) then
                TriggerServerEvent('tmg-weapons:server:TakeBackWeapon', key, data)
            end
        end
    else
        if CurrentWeaponData and next(CurrentWeaponData) then
            if not data.cachedCost then
                local WeaponData = TMGCore.Shared.Weapons[GetHashKey(CurrentWeaponData.name)]
                local WeaponClass = (TMGCore.Shared.SplitStr(WeaponData.ammotype, '_')[2]):lower()
                data.cachedCost = Config.WeaponRepairCosts[WeaponClass]
            end
            
            DrawText3Ds(data.coords.x, data.coords.y, data.coords.z, Lang:t('info.repair_weapon_price', { value = data.cachedCost }))
            
            if IsControlJustPressed(0, 38) then
                TMGCore.Functions.TriggerCallback('tmg-weapons:server:RepairWeapon', function(HasMoney)
                    if HasMoney then 
                        CurrentWeaponData = {} 
                        data.cachedCost = nil
                    end
                end, key, CurrentWeaponData)
            end
        end
    end
end

RegisterNetEvent('TMGCore:Client:OnPlayerUnload', function()
    for k in pairs(Config.WeaponRepairPoints) do
        Config.WeaponRepairPoints[k].IsRepairing = false
        Config.WeaponRepairPoints[k].RepairingData = {}
    end

    CurrentWeaponData = {}
    currentWeapon = nil
    MultiplierAmount = 0
    CanShoot = true
    
    currentRepairPoint = nil
    isCheckingThrowable = false
    
    local ped = PlayerPedId()
    RemoveAllPedWeapons(ped, true)
    
    TriggerEvent('tmg-weapons:ResetHolster')
end)



local function DrawText3Ds(x, y, z, text)
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    BeginTextCommandDisplayText('STRING')
    SetTextCentre(true)
    AddTextComponentSubstringPlayerName(text)
    SetDrawOrigin(x, y, z, 0)
    EndTextCommandDisplayText(0.0, 0.0)
    local factor = (string.len(text)) / 370
    DrawRect(0.0, 0.0 + 0.0125, 0.017 + factor, 0.03, 0, 0, 0, 75)
    ClearDrawOrigin()
end




RegisterNetEvent('tmg-weapons:client:SyncRepairShops', function(NewData, key)
    if not Config.WeaponRepairPoints[key] then 
        return print(string.format("^1[TMG Mainframe] Sync Error: Key %s does not exist in local Config!^7", tostring(key)))
    end

    if type(NewData) ~= "table" then return end

    Config.WeaponRepairPoints[key].IsRepairing = NewData.IsRepairing or false
    Config.WeaponRepairPoints[key].RepairingData = NewData.RepairingData or {}

    Config.WeaponRepairPoints[key].cachedCost = nil

    if currentRepairPoint == key then
        local citizenid = TMGCore.Functions.GetPlayerData().citizenid
        if NewData.RepairingData and NewData.RepairingData.CitizenId == citizenid and NewData.RepairingData.Ready then
            TMGCore.Functions.Notify(Lang:t('info.take_weapon_back'), 'success')
        end
    end
end)

RegisterNetEvent('tmg-weapons:client:EquipTint', function(weaponHash, tintIndex)
    local ped = PlayerPedId()
    
    local weapon = tonumber(weaponHash)
    local tint = tonumber(tintIndex) or 0
    
    if not weapon then return end

    if GetSelectedPedWeapon(ped) == weapon then
        SetPedWeaponTintIndex(ped, weapon, tint)
        
        if CurrentWeaponData and joaat(CurrentWeaponData.name) == weapon then
            if not CurrentWeaponData.info then CurrentWeaponData.info = {} end
            CurrentWeaponData.info.tint = tint
        end
    else
        print(string.format("^3[TMG Mainframe] Tint deferred: Player not holding weapon 0x%X^7", weapon))
    end
end)


RegisterNetEvent('tmg-weapons:client:SetCurrentWeapon', function(data, bool)
    if data and type(data) == "table" then
        for k, v in pairs(data) do
            CurrentWeaponData[k] = v
        end
        for k in pairs(CurrentWeaponData) do
            if data[k] == nil then CurrentWeaponData[k] = nil end
        end
    else
        table.wipe(CurrentWeaponData)
    end

    CanShoot = (data ~= false and data ~= nil) and bool or false

    LocalPlayer.state:set("currentWeaponHash", data and joaat(data.name) or 0, true)

    if Config.Debug then
        local weaponName = data and data.name or "Unarmed"
        print(string.format("^2[TMG Mainframe] Weapon Sync: %s | CanShoot: %s^7", weaponName, tostring(CanShoot)))
    end
end)

local qualityBuffer = 0
local isSyncing = false

RegisterNetEvent('tmg-weapons:client:SetWeaponQuality', function(amount)
    if not CurrentWeaponData or not next(CurrentWeaponData) then return end
    
    qualityBuffer = qualityBuffer + amount

    if qualityBuffer >= 5 and not isSyncing then
        isSyncing = true
        
        local weaponSlot = CurrentWeaponData.slot
        
        TriggerServerEvent('tmg-weapons:server:SetWeaponQuality', weaponSlot, qualityBuffer)
        
        if CurrentWeaponData.info then
            CurrentWeaponData.info.quality = CurrentWeaponData.info.quality - qualityBuffer
        end
        
        qualityBuffer = 0
        
        SetTimeout(1000, function()
            isSyncing = false
        end)
    end
end)

RegisterNetEvent('tmg-weapons:client:AddAmmo', function(ammoType, amount, itemData)
    local ped = PlayerPedId()
    local weaponHash = GetSelectedPedWeapon(ped)
    if not CurrentWeaponData or not next(CurrentWeaponData) then
        return TMGCore.Functions.Notify(Lang:t('error.no_weapon'), 'error')
    end

    local reloadSnapshot = {
        item = CurrentWeaponData.name,
        slot = CurrentWeaponData.slot,
        hash = weaponHash
    }

    local weaponConfig = TMGCore.Shared.Weapons[weaponHash]
    if not weaponConfig or weaponConfig.name == 'weapon_unarmed' then
        return TMGCore.Functions.Notify(Lang:t('error.no_weapon_in_hand'), 'error')
    end

    if weaponConfig.ammotype ~= ammoType:upper() then
        return TMGCore.Functions.Notify(Lang:t('error.wrong_ammo'), 'error')
    end

    local currentAmmo = GetAmmoInPedWeapon(ped, weaponHash)
    local _, maxAmmo = GetMaxAmmo(ped, weaponHash)

    if currentAmmo >= maxAmmo then
        return TMGCore.Functions.Notify(Lang:t('error.max_ammo'), 'error')
    end

    TMGCore.Functions.Progressbar('taking_bullets', Lang:t('info.loading_bullets'), Config.ReloadTime, false, true, {
        disableMovement = false,
        disableCarMovement = false,
        disableMouse = false,
        disableCombat = true,
    }, {}, {}, {}, function() 
        local postWeaponHash = GetSelectedPedWeapon(ped)
        
        if postWeaponHash ~= reloadSnapshot.hash then
            return TMGCore.Functions.Notify("Reload failed: Weapon mismatch during loading.", "error")
        end

        if not CurrentWeaponData or CurrentWeaponData.slot ~= reloadSnapshot.slot then
            return TMGCore.Functions.Notify("Reload failed: Inventory state changed.", "error")
        end

        TriggerServerEvent('tmg-weapons:server:AddAmmoToWeapon', reloadSnapshot.slot, amount, itemData)
        
        TaskReloadWeapon(ped, false)
        TriggerEvent('tmg-inventory:client:ItemBox', TMGCore.Shared.Items[itemData.name], 'remove')
    end, function() 
        TMGCore.Functions.Notify(Lang:t('error.canceled'), 'error')
    end)
end)

local throwableWeapons = {
    ['weapon_stickybomb'] = true, ['weapon_pipebomb'] = true, ['weapon_smokegrenade'] = true,
    ['weapon_flare'] = true, ['weapon_proxmine'] = true, ['weapon_ball'] = true,
    ['weapon_molotov'] = true, ['weapon_grenade'] = true, ['weapon_bzgas'] = true
}

RegisterNetEvent('tmg-weapons:client:UseWeapon', function(weaponData, shootbool)
    local ped = PlayerPedId()
    local weaponName = tostring(weaponData.name)
    local weaponHash = joaat(weaponName)

    if currentWeapon == weaponName then
        TriggerEvent('tmg-weapons:client:DrawWeapon', nil)
        SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
        
        RemoveWeaponFromPed(ped, weaponHash) 
        
        TriggerEvent('tmg-weapons:client:SetCurrentWeapon', nil, shootbool)
        currentWeapon = nil
        return
    end

    if currentWeapon then
        RemoveWeaponFromPed(ped, joaat(currentWeapon))
    end

    if throwableWeapons[weaponName] then
        TriggerEvent('tmg-weapons:client:DrawWeapon', weaponName)
        GiveWeaponToPed(ped, weaponHash, 1, false, true) 
        SetPedAmmo(ped, weaponHash, 1)
        
    elseif weaponName == 'weapon_snowball' then
        TriggerEvent('tmg-weapons:client:DrawWeapon', weaponName)
        GiveWeaponToPed(ped, weaponHash, 10, false, true)
        SetPedAmmo(ped, weaponHash, 10)
        TriggerServerEvent('tmg-inventory:server:snowball', 'remove')
        
    else
        TriggerEvent('tmg-weapons:client:DrawWeapon', weaponName)
        
        local ammo = tonumber(weaponData.info.ammo) or 0
        if weaponName == 'weapon_petrolcan' or weaponName == 'weapon_fireextinguisher' then
            ammo = 4000
        end

        GiveWeaponToPed(ped, weaponHash, ammo, false, true)
        SetPedAmmo(ped, weaponHash, ammo)

        if weaponData.info.attachments then
            for i = 1, #weaponData.info.attachments do
                local componentHash = joaat(weaponData.info.attachments[i].component)
                if not HasPedGotWeaponComponent(ped, weaponHash, componentHash) then
                    GiveWeaponComponentToPed(ped, weaponHash, componentHash)
                end
            end
        end

        if weaponData.info.tint then
            SetPedWeaponTintIndex(ped, weaponHash, weaponData.info.tint)
        end
    end

    SetCurrentPedWeapon(ped, weaponHash, true)
    TriggerEvent('tmg-weapons:client:SetCurrentWeapon', weaponData, shootbool)
    currentWeapon = weaponName
end)


RegisterNetEvent('tmg-weapons:client:CheckWeapon', function(weaponName)
    local targetWeapon = tostring(weaponName):lower()
    local activeWeapon = currentWeapon and currentWeapon:lower() or nil

    if activeWeapon ~= targetWeapon then return end

    local ped = PlayerPedId()
    local weaponHash = GetSelectedPedWeapon(ped)

    TriggerEvent('tmg-weapons:ResetHolster')
    
    SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)

    if weaponHash ~= `WEAPON_UNARMED` then
        RemoveWeaponFromPed(ped, weaponHash)
    end

    currentWeapon = nil
    MultiplierAmount = 0
    
    LocalPlayer.state:set("currentWeaponHash", 0, true)
    
    if Config.Debug then
        print(string.format("^3[TMG Mainframe] Forced Holster: %s removed from active state.^7", targetWeapon))
    end
end)



local isCheckingThrowable = false
local cachedRepairCosts = {} 

CreateThread(function()
    SetWeaponsNoAutoswap(true)
    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        
        if IsPedArmed(ped, 7) then
            sleep = 0
            if IsControlJustReleased(0, 24) or IsDisabledControlJustReleased(0, 24) then
                local weapon = GetSelectedPedWeapon(ped)
                local ammo = GetAmmoInPedWeapon(ped, weapon)
                
                TriggerServerEvent('tmg-weapons:server:UpdateWeaponAmmo', CurrentWeaponData, tonumber(ammo))
                
                if MultiplierAmount > 0 then
                    TriggerServerEvent('tmg-weapons:server:UpdateWeaponQuality', CurrentWeaponData, MultiplierAmount)
                    MultiplierAmount = 0
                end
            end
        end
        Wait(sleep)
    end
end)

CreateThread(function()
    while true do
        local sleep = 500
        if LocalPlayer.state.isLoggedIn and CurrentWeaponData and next(CurrentWeaponData) then
            local ped = PlayerPedId()
            if IsPedShooting(ped) then
                sleep = 0
                if CanShoot then
                    local weapon = GetSelectedPedWeapon(ped)
                    if not isCheckingThrowable and weapon ~= 0 then
                        isCheckingThrowable = true
                        TMGCore.Functions.TriggerCallback('prison:server:checkThrowable', function(isThrowable)
                            if not isThrowable and GetAmmoInPedWeapon(ped, weapon) > 0 then
                                MultiplierAmount = MultiplierAmount + 1
                            end
                            
                            SetTimeout(200, function() isCheckingThrowable = false end)
                        end, weapon)
                    end
                else
                    local weaponHash = GetSelectedPedWeapon(ped)
                    if weaponHash ~= `WEAPON_UNARMED` then
                        TriggerEvent('tmg-weapons:client:CheckWeapon', TMGCore.Shared.Weapons[weaponHash]['name'])
                        TMGCore.Functions.Notify(Lang:t('error.weapon_broken'), 'error')
                        MultiplierAmount = 0
                    end
                end
            end
        end
        Wait(sleep)
    end
end)
CreateThread(function()
    while true do
        local sleep = 1500 
        if LocalPlayer.state.isLoggedIn then
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            local inRange = false

            for k, data in pairs(Config.WeaponRepairPoints) do
                local dist = #(pos - data.coords)
                
                if dist < 10 then
                    inRange = true
                    sleep = 0 
                    
                    if dist < 1.5 then
                        HandleRepairInteraction(k, data)
                    end
                    break 
                end
            end
        end
        Wait(sleep)
    end
end)

function HandleRepairInteraction(key, data)
    if data.IsRepairing then
        if data.RepairingData.CitizenId ~= PlayerData.citizenid then
            DrawText3Ds(data.coords.x, data.coords.y, data.coords.z, Lang:t('info.repairshop_not_usable'))
        elseif not data.RepairingData.Ready then
            DrawText3Ds(data.coords.x, data.coords.y, data.coords.z, Lang:t('info.weapon_will_repair'))
        else
            DrawText3Ds(data.coords.x, data.coords.y, data.coords.z, Lang:t('info.take_weapon_back'))
            if IsControlJustPressed(0, 38) then
                TriggerServerEvent('tmg-weapons:server:TakeBackWeapon', key, data)
            end
        end
    else
        if CurrentWeaponData and next(CurrentWeaponData) then
            if not data.RepairingData.Ready then
                local weaponName = CurrentWeaponData.name
                if not cachedRepairCosts[weaponName] then
                    local WeaponData = TMGCore.Shared.Weapons[GetHashKey(weaponName)]
                    local WeaponClass = (TMGCore.Shared.SplitStr(WeaponData.ammotype, '_')[2]):lower()
                    cachedRepairCosts[weaponName] = Config.WeaponRepairCosts[WeaponClass]
                end

                DrawText3Ds(data.coords.x, data.coords.y, data.coords.z, Lang:t('info.repair_weapon_price', { value = cachedRepairCosts[weaponName] }))
                
                if IsControlJustPressed(0, 38) then
                    TMGCore.Functions.TriggerCallback('tmg-weapons:server:RepairWeapon', function(HasMoney)
                        if HasMoney then CurrentWeaponData = {} end
                    end, key, CurrentWeaponData)
                end
            else
                if data.RepairingData.CitizenId == PlayerData.citizenid then
                    DrawText3Ds(data.coords.x, data.coords.y, data.coords.z, Lang:t('info.take_weapon_back'))
                    if IsControlJustPressed(0, 38) then
                        TriggerServerEvent('tmg-weapons:server:TakeBackWeapon', key, data)
                    end
                end
            end
        end
    end
end
