local TMGCore = exports['tmg-core']:GetCoreObject()



local function IsWeaponBlocked(weaponName)
    if Config.DurabilityBlockedWeapons[weaponName] then
        return true
    end

    return false
end



TMGCore.Functions.CreateCallback('tmg-weapons:server:GetConfig', function(source, cb)
    local publicPoints = {}

    for k, v in pairs(Config.WeaponRepairPoints) do
        publicPoints[k] = {
            coords = v.coords,
            label  = v.label,
            isRepairing = v.IsRepairing or false 
        }
    end
    cb(publicPoints)
    
    print(string.format("^5[TMG]^7 Metadata: Streamed %s repair nodes to Terminal %s", #publicPoints, source))
end)

TMGCore.Functions.CreateCallback('weapon:server:GetWeaponAmmo', function(source, cb, weaponData)
    if not weaponData or not weaponData.slot then return cb(0, "unknown") end
    
    local Player = TMGCore.Functions.GetPlayer(source)
    if not Player then return cb(0, weaponData.name) end

    local item = Player.Functions.GetItemBySlot(weaponData.slot)
    
    local ammoCount = (item and item.info and item.info.ammo) or 0

    cb(ammoCount, weaponData.name)
    
    print(string.format("^5[TMG]^7 Ballistics: Terminal %s retrieved %s rounds for %s", source, ammoCount, weaponData.name))
end)


TMGCore.Functions.CreateCallback('tmg-weapons:server:RepairWeapon', function(source, cb, repairPoint, data)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player then return cb(false) end

    local weaponItem = Player.Functions.GetItemBySlot(data.slot)
    if not weaponItem or weaponItem.name ~= data.name then
        TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.no_weapon_in_hand'), 'error')
        return cb(false)
    end

    local weaponData = TMGCore.Shared.Weapons[GetHashKey(data.name)]
    local weaponClass = (TMGCore.Shared.SplitStr(weaponData.ammotype, '_')[2]):lower()
    local repairCost = Config.WeaponRepairCosts[weaponClass] or 500

    if (weaponItem.info.quality or 100) >= 100 then
        TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.no_damage_on_weapon'), 'error')
        return cb(false)
    end

    if not Player.Functions.RemoveMoney('cash', repairCost, "weapon-repair-service") then
        return cb(false)
    end

    if exports['tmg-inventory']:RemoveItem(src, data.name, 1, data.slot) then
        
        Config.WeaponRepairPoints[repairPoint].IsRepairing = true
        Config.WeaponRepairPoints[repairPoint].RepairingData = {
            citizenid = Player.PlayerData.citizenid,
            weaponItem = weaponItem, 
            ready = false,
        }

        TriggerClientEvent('tmg-inventory:client:ItemBox', src, TMGCore.Shared.Items[data.name], 'remove')
        TriggerClientEvent('tmg-weapons:client:SyncRepairShops', -1, Config.WeaponRepairPoints[repairPoint], repairPoint)

        local timeout = math.random(5 * 60000, 10 * 60000)
        
        SetTimeout(timeout, function()
            Config.WeaponRepairPoints[repairPoint].IsRepairing = false
            Config.WeaponRepairPoints[repairPoint].RepairingData.ready = true
            
            TriggerClientEvent('tmg-weapons:client:SyncRepairShops', -1, Config.WeaponRepairPoints[repairPoint], repairPoint)

            exports['tmg-phone']:sendNewMailToOffline(Player.PlayerData.citizenid, {
                sender = "Gunsmith",
                subject = "Service Complete",
                message = string.format("Your %s has been restored to factory specs and is ready for pickup.", weaponData.label)
            })

            SetTimeout(7 * 60000, function()
                if Config.WeaponRepairPoints[repairPoint].RepairingData.ready then
                    Config.WeaponRepairPoints[repairPoint].IsRepairing = false
                    Config.WeaponRepairPoints[repairPoint].RepairingData = {}
                    TriggerClientEvent('tmg-weapons:client:SyncRepairShops', -1, Config.WeaponRepairPoints[repairPoint], repairPoint)
                end
            end)
        end)
        
        cb(true)
    else
        Player.Functions.AddMoney('cash', repairCost, "repair-refund")
        cb(false)
    end
end)



TMGCore.Functions.CreateCallback('prison:server:checkThrowable', function(source, cb, weaponHash)
    local Player = TMGCore.Functions.GetPlayer(source)
    if not Player or not weaponHash then return cb(false) end

    local weaponData = TMGCore.Shared.Weapons[weaponHash]
    if not weaponData then return cb(false) end
    
    local weaponName = weaponData.name:lower()

    local throwableKey = weaponName:gsub("weapon_", "")

    if Config.Throwables[throwableKey] then
        
        if exports['tmg-inventory']:RemoveItem(source, weaponName, 1, false, 'prison-throwable-consume') then
            
            TriggerClientEvent('tmg-inventory:client:ItemBox', source, TMGCore.Shared.Items[weaponName], 'remove')
            return cb(true)
        end
    end

    cb(false)
end)

RegisterNetEvent('tmg-weapons:server:updateWeaponAmmo', function(currentWeaponData, amount)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player or not currentWeaponData then return end

    local amount = math.floor(tonumber(amount) or 0)
    local slot = currentWeaponData.slot

    if Player.PlayerData.items[slot] then
        Player.PlayerData.items[slot].info.ammo = amount

        local updatePath = string.format("inventory.%d.info.ammo", slot)
        
        exports['tmgnosql']:UpdateOne('players', 
            { ["citizenid"] = Player.PlayerData.citizenid }, 
            { 
                ["$set"] = { [updatePath] = amount } 
            }, 
            function(success)
                if not success then
                    print(string.format("^1[TMG Error]^7 Ballistic Desync: Citizen %s ammo failed to anchor.", Player.PlayerData.citizenid))
                end
            end
        )
    end
end)

RegisterNetEvent('tmg-weapons:server:TakeBackWeapon', function(k)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player then return end

    local repairNode = Config.WeaponRepairPoints[k]
    if not repairNode or not repairNode.RepairingData then return end

    if repairNode.RepairingData.citizenid ~= Player.PlayerData.citizenid then
        return TriggerClientEvent('TMGCore:Notify', src, "Mainframe: Biometric mismatch. This is not your asset.", 'error')
    end

    if not repairNode.RepairingData.ready then
        return TriggerClientEvent('TMGCore:Notify', src, "Mainframe: Maintenance cycle incomplete.", 'error')
    end

    local itemData = repairNode.RepairingData.weaponItem
    itemData.info.quality = 100 

    if exports['tmg-inventory']:AddItem(src, itemData.name, 1, false, itemData.info, 'tmg-weapons:server:TakeBackWeapon') then
        
        TriggerClientEvent('tmg-inventory:client:ItemBox', src, TMGCore.Shared.Items[itemData.name], 'add')
        
        Config.WeaponRepairPoints[k].IsRepairing = false
        Config.WeaponRepairPoints[k].RepairingData = {}
        
        TriggerClientEvent('tmg-weapons:client:SyncRepairShops', -1, Config.WeaponRepairPoints[k], k)
        
        print(string.format("^5[TMG]^7 Restoration: %s reclaimed restored %s", Player.PlayerData.citizenid, itemData.name))
    else
        TriggerClientEvent('TMGCore:Notify', src, "Mainframe: Inventory overflow. Asset remains in sequestration.", 'error')
    end
end)

RegisterNetEvent('tmg-weapons:server:SetWeaponQuality', function(data, hp)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player or not data or not data.slot then return end

    local newQuality = math.max(0.0, math.min(100.0, tonumber(hp) or 100.0))
    local slot = data.slot

    if Player.PlayerData.items[slot] then
        Player.PlayerData.items[slot].info.quality = TMGCore.Shared.Round(newQuality, 2)

        local updatePath = string.format("inventory.%d.info.quality", slot)
        
        exports['tmgnosql']:UpdateOne('players', 
            { ["citizenid"] = Player.PlayerData.citizenid }, 
            { 
                ["$set"] = { [updatePath] = Player.PlayerData.items[slot].info.quality } 
            }, 
            function(success)
                if not success then
                    print(string.format("^1[TMG Error]^7 Quality Sync Failure: Citizen %s, Slot %s", Player.PlayerData.citizenid, slot))
                end
            end
        )
    end
end)

RegisterNetEvent('tmg-weapons:server:UpdateWeaponQuality', function(data, repeatAmount)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player or not data or not data.slot then return end

    local slot = data.slot
    local item = Player.PlayerData.items[slot]
    if not item then return end

    local weaponName = data.name:lower()
    if IsWeaponBlocked(weaponName) then return end

    local multiplier = Config.DurabilityMultiplier[weaponName] or 0.15
    local totalDecrease = multiplier * (tonumber(repeatAmount) or 1)
    
    local currentQuality = item.info.quality or 100
    local newQuality = math.max(0, TMGCore.Shared.Round(currentQuality - totalDecrease, 2))

    item.info.quality = newQuality

    if newQuality <= 0 then
        TriggerClientEvent('tmg-weapons:client:UseWeapon', src, data, false)
        TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.weapon_broken_need_repair'), 'error')
    end

    local updatePath = string.format("inventory.%d.info.quality", slot)
    
    exports['tmgnosql']:UpdateOne('players', 
        { ["citizenid"] = Player.PlayerData.citizenid }, 
        { 
            ["$set"] = { [updatePath] = newQuality } 
        },
        function(success)
            if not success then
                print(string.format("^1[TMG Error]^7 Durability sync failed for CID %s", Player.PlayerData.citizenid))
            end
        end
    )
end)

RegisterNetEvent('tmg-weapons:server:removeWeaponAmmoItem', function(item)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    
    if not Player or type(item) ~= 'table' or not item.name or not item.slot then return end

    if not Config.AmmoTypes[item.name] then
        print(string.format("^1[TMG]^7 Security: Terminal %s attempted to purge non-ammo asset [%s]", src, item.name))
        return 
    end

    local success = exports['tmg-inventory']:RemoveItem(src, item.name, 1, item.slot, 'ballistic-reload-purge')
    
    if success then
        TriggerClientEvent('tmg-inventory:client:ItemBox', src, TMGCore.Shared.Items[item.name], 'remove')
        
        print(string.format("^5[TMG]^7 Ballistics: Terminal %s consumed 1x %s", src, item.name))
    end
end)



TMGCore.Commands.Add('repairweapon', 'Repair Weapon (God Only)', { 
    { name = 'hp', help = Lang:t('info.hp_of_weapon') } 
}, true, function(source, args)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player then return end

    local newHP = tonumber(args[1]) or 100
    newHP = math.max(0, math.min(100, newHP))

    TriggerClientEvent('tmg-weapons:client:GetSelectedWeapon', src, function(weaponData)
        if not weaponData or not weaponData.slot then 
            return TriggerClientEvent('TMGCore:Notify', src, "Mainframe: No active ballistic asset detected in hand.", 'error') 
        end

        local slot = weaponData.slot
        
        if Player.PlayerData.items[slot] then
            Player.PlayerData.items[slot].info.quality = newHP
            
            local updatePath = string.format("inventory.%d.info.quality", slot)
            
            exports['tmgnosql']:UpdateOne('players', 
                { ["citizenid"] = Player.PlayerData.citizenid }, 
                {
                    ["$set"] = { [updatePath] = newHP }
                }, 
                function(success)
                    if success then
                        TriggerClientEvent('tmg-weapons:client:SetWeaponQuality', src, newHP)
                        TriggerClientEvent('TMGCore:Notify', src, "Mainframe: Asset integrity restored to " .. newHP .. "%", 'success')
                        
                        print(string.format("^5[TMG]^7 Admin: %s forced repair on Slot %s to %d%%", Player.PlayerData.citizenid, slot, newHP))
                    else
                        TriggerClientEvent('TMGCore:Notify', src, "Mainframe Error: Registry rejection.", 'error')
                    end
                end
            )
        end
    end)
end, 'god')




for ammoItem, properties in pairs(Config.AmmoTypes) do
    TMGCore.Functions.CreateUseableItem(ammoItem, function(source, item)
        local src = source
        local Player = TMGCore.Functions.GetPlayer(src)
        if not Player then return end
        local itemData = Player.Functions.GetItemBySlot(item.slot)
        if not itemData or itemData.name ~= ammoItem then return end
        TriggerClientEvent('tmg-weapons:client:AddAmmo', src, properties.ammoType, properties.amount, item)
        print(string.format("^5[TMG]^7 Materialization: %s consumed 1x %s", Player.PlayerData.citizenid, ammoItem))
    end)
end


local function EquipWeaponTint(source, tintIndex, itemName, isMK2)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player then return end

    local ped = GetPlayerPed(src)
    local weaponHash = GetSelectedPedWeapon(ped)

    if weaponHash == `WEAPON_UNARMED` then
        return TriggerClientEvent('TMGCore:Notify', src, 'Mainframe: No active asset detected for modification.', 'error')
    end

    local weaponData = TMGCore.Shared.Weapons[weaponHash]
    if not weaponData then return end
    
    if isMK2 and not IsMK2Weapon(weaponHash) then
        return TriggerClientEvent('TMGCore:Notify', src, 'Incompatible Tech: This tint requires an MK2 receiver.', 'error')
    end
    local item, slot = GetWeaponSlotByName(Player.PlayerData.items, weaponData.name)
    if not item or not slot then return end

    if (item.info.tint or -1) == tintIndex then
        return TriggerClientEvent('TMGCore:Notify', src, 'Visual state already matches requested tint.', 'error')
    end

    item.info.tint = tintIndex
    Player.PlayerData.items[slot] = item

    local updatePath = string.format("inventory.%d.info.tint", slot)
    
    exports['tmgnosql']:UpdateOne('players', 
        { ["citizenid"] = Player.PlayerData.citizenid }, 
        { 
            ["$set"] = { [updatePath] = tintIndex } 
        }, 
        function(success)
            if not success then
                print(string.format("^1[TMG Error]^7 Cosmetic Sync Failure: CID %s", Player.PlayerData.citizenid))
            end
        end
    )

    if exports['tmg-inventory']:RemoveItem(src, itemName, 1, false, 'ballistic-tint-apply') then
        TriggerClientEvent('tmg-inventory:client:ItemBox', src, TMGCore.Shared.Items[itemName], 'remove')
        TriggerClientEvent('tmg-weapons:client:EquipTint', src, weaponHash, tintIndex)
        
        print(string.format("^5[TMG]^7 Cosmetic: CID %s applied tint %d to slot %d", Player.PlayerData.citizenid, tintIndex, slot))
    end
end

local function EquipWeaponAttachment(src, item)
    local ped = GetPlayerPed(src)
    local selectedWeaponHash = GetSelectedPedWeapon(ped)
    
    if selectedWeaponHash == `WEAPON_UNARMED` then return end
    local weaponName = TMGCore.Shared.Weapons[selectedWeaponHash].name

    local attachmentComponent = DoesWeaponTakeWeaponComponent(item, weaponName)
    if not attachmentComponent then
        return TriggerClientEvent('TMGCore:Notify', src, 'Mainframe: Hardware incompatibility detected.', 'error')
    end

    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player then return end
    local weaponSlot, weaponIndex = GetWeaponSlotByName(Player.PlayerData.items, weaponName)
    if not weaponSlot or not weaponIndex then return end

    weaponSlot.info.attachments = weaponSlot.info.attachments or {}
    local hasAttach, attachIndex = HasAttachment(attachmentComponent, weaponSlot.info.attachments)
    local shouldRemoveItem = false

    if hasAttach then
        RemoveWeaponComponentFromPed(ped, selectedWeaponHash, attachmentComponent)
        table.remove(weaponSlot.info.attachments, attachIndex)
        
        exports['tmg-inventory']:AddItem(src, item, 1, false, {}, 'ballistic-detach-return')
        TriggerClientEvent('tmg-inventory:client:ItemBox', src, TMGCore.Shared.Items[item], 'add')
    else
        weaponSlot.info.attachments[#weaponSlot.info.attachments + 1] = { component = attachmentComponent }
        GiveWeaponComponentToPed(ped, selectedWeaponHash, attachmentComponent)
        shouldRemoveItem = true
    end

    local updatePath = string.format("inventory.%d.info.attachments", weaponIndex)
    
    exports['tmgnosql']:UpdateOne('players', 
        { ["citizenid"] = Player.PlayerData.citizenid }, 
        { 
            ["$set"] = { [updatePath] = weaponSlot.info.attachments } 
        }, 
        function(success)
            if not success then
                print(string.format("^1[TMG Error]^7 Attachment Sync Failure: CID %s", Player.PlayerData.citizenid))
            end
        end
    )

    if shouldRemoveItem then
        exports['tmg-inventory']:RemoveItem(src, item, 1, false, 'ballistic-attach-consume')
        TriggerClientEvent('tmg-inventory:client:ItemBox', src, TMGCore.Shared.Items[item], 'remove')
    end
end

for attachmentItem in pairs(WeaponAttachments) do
    TMGCore.Functions.CreateUseableItem(attachmentItem, function(source, item)
        EquipWeaponAttachment(source, item.name)
    end)
end
