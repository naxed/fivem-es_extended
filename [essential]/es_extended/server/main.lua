RegisterServerEvent('esx:clientLog')
AddEventHandler('esx:clientLog', function(str)
	RconPrint('esx:clientLog => ' .. str)
end)

AddEventHandler('es:newPlayerLoaded', function(source, _user)
	TriggerClientEvent('esx:requestClientInfos', source)
end)

RegisterServerEvent('esx:responseClientInfos')
AddEventHandler('esx:responseClientInfos', function(infos)

	local _source = source

	TriggerEvent('es:getPlayerFromId', _source, function(user)

		MySQL:executeQuery("UPDATE users SET name = '@name' WHERE identifier = '@identifier'", {['@identifier'] = user.identifier, ['@name'] = infos.playerName})

		local accounts = {}

		local executed_query  = MySQL:executeQuery("SELECT * FROM user_accounts WHERE identifier = '@identifier'", {['@identifier'] = user.identifier})
		local result          = MySQL:getResults(executed_query, {'name', 'money'}, "id")

		for i=1, #result, 1 do
			accounts[i] = {
				name  = result[i].name,
				money = result[i].money
			}
		end

		local inventory      = {}
		local executed_query = MySQL:executeQuery("SELECT * FROM user_inventory WHERE identifier = '@identifier'", {['@identifier'] = user.identifier})
		local result         = MySQL:getResults(executed_query, {'item', 'count'}, "id")

		for i=1, #result, 1 do
			table.insert(inventory, {
				item   = result[i].item,
				count  = result[i].count,
				label  = Items[result[i].item].label,
				limit  = Items[result[i].item].limit,
				usable = UsableItemsCallbacks[result[i].item] ~= nil
			})
		end

		for k,v in pairs(Items) do

			local found = false

			for j=1, #inventory, 1 do
				if inventory[j].item == k then
					found = true
					break
				end
			end

			if not found then
				
				table.insert(inventory, {
					item   = k,
					count  = 0,
					label  = Items[k].label,
					limit  = Items[k].limit,
					usable = UsableItemsCallbacks[k] ~= nil
				})

				MySQL:executeQuery("INSERT INTO user_inventory (identifier, item, count) VALUES ('@identifier', '@item', '@count')", {['@identifier'] = user.identifier, ['@item'] = k, ['@count'] = 0})
			end

		end

		local job = {}

		local executed_query  = MySQL:executeQuery("SELECT * FROM users WHERE identifier = '@identifier'", {['@identifier'] = user.identifier})
		local result          = MySQL:getResults(executed_query, {'skin', 'job', 'job_grade', 'loadout'})

		job['name']  = result[1].job
		job['grade'] = result[1].job_grade

		local loadout = {}

		if result[1].loadout ~= nil then
			loadout = json.decode(result[1].loadout)
		end

		local executed_query  = MySQL:executeQuery("SELECT * FROM jobs WHERE name = '@name'", {['@name'] = job.name})
		local result          = MySQL:getResults(executed_query, {'id', 'name', 'label'})

		job['id']    = result[1].id
		job['name']  = result[1].name
		job['label'] = result[1].label

		local executed_query  = MySQL:executeQuery("SELECT * FROM job_grades WHERE job_name = '@job_name' AND grade = '@grade'", {['@job_name'] = job.name, ['@grade'] = job.grade})
		local result          = MySQL:getResults(executed_query, {'name', 'label', 'salary', 'skin_male', 'skin_female'})

		job['grade_name']   = result[1].name
		job['grade_label']  = result[1].label
		job['grade_salary'] = result[1].salary

		job['skin_male']   = {}
		job['skin_female'] = {}

		if result[1].skin_male ~= nil then
			job['skin_male'] = json.decode(result[1].skin_male)
		end

		if result[1].skin_female ~= nil then
			job['skin_female'] = json.decode(result[1].skin_female)
		end

		local xPlayer         = ExtendedPlayer(user, accounts, inventory, job, loadout, infos.playerName)
		local missingAccounts = xPlayer:getMissingAccounts()

		if #missingAccounts > 0 then

			for i=1, #missingAccounts, 1 do
				table.insert(xPlayer.accounts, {
					name  = missingAccounts[i],
					money = 0
				})
			end

			xPlayer:createAccounts(missingAccounts)
		end

		Users[_source] = xPlayer

		TriggerEvent('esx:playerLoaded', _source)
		TriggerClientEvent('esx:playerLoaded', _source)

		TriggerClientEvent('es:activateMoney',  _source, xPlayer.player.money)
		TriggerClientEvent('esx:activateMoney', _source, xPlayer.accounts)
		
		TriggerClientEvent('esx:setJob', _source, xPlayer.job)

	end)

end)

RegisterServerEvent('esx:getPlayerFromId')
AddEventHandler('esx:getPlayerFromId', function(source, cb)
	cb(Users[source])
end)

AddEventHandler('esx:getPlayers', function(cb)
	cb(Users)
end)

RegisterServerEvent('esx:updateLoadout')
AddEventHandler('esx:updateLoadout', function(loadout)
	TriggerEvent('esx:getPlayerFromId', source, function(xPlayer)
		xPlayer.loadout = loadout
	end)
end)

RegisterServerEvent('esx:requestLoadout')
AddEventHandler('esx:requestLoadout', function()
	local _source = source
	TriggerEvent('esx:getPlayerFromId', source, function(xPlayer)
		TriggerClientEvent('esx:responseLoadout', _source, xPlayer.loadout)
	end)
end)

AddEventHandler('playerDropped', function()

	local _source = source

	if Users[_source] ~= nil then

		TriggerEvent('esx:playerDropped',  _source)

		local query = ''

		-- User accounts
		local itemCount = 0
		local subQuery  = '';

		for i=1, #Users[_source].accounts, 1 do
			subQuery = subQuery .. "UPDATE user_accounts SET `money`='" .. Users[_source].accounts[i].money .. "' WHERE identifier = '" .. Users[_source].identifier .. "' AND name = '" .. Users[_source].accounts[i].name .. "';"
			itemCount = itemCount + 1
		end

		if itemCount > 0 then
			query = query .. subQuery
		end

		-- Inventory items
		local subQuery  = ''
		local itemCount = 0

		for i=1, #Users[_source].inventory, 1 do
			subQuery  = subQuery .. "UPDATE user_inventory SET `count`='" .. Users[_source].inventory[i].count .. "' WHERE identifier = '" .. Users[_source].identifier .. "' AND item = '" .. Users[_source].inventory[i].item .. "';"
			itemCount = itemCount + 1
		end

		if itemCount > 0 then
			query = query .. subQuery
		end

		-- Job, loadout and position
		query = query .. "UPDATE users SET job = '" .. Users[_source].job.name .. "', job_grade = '" .. Users[_source].job.grade .. "', loadout = '" .. json.encode(Users[_source].loadout) .. "', position='" .. json.encode(Users[_source].player.coords) .. "' WHERE identifier = '" .. Users[_source].identifier .. "';"

		Users[_source] = nil

		MySQL:executeQuery(query)

	end

end)

RegisterServerEvent('esx:requestPlayerDataForGUI')
AddEventHandler('esx:requestPlayerDataForGUI', function()

	local _source = source

	TriggerEvent('esx:getPlayerFromId', _source, function(xPlayer)

		local data = {
			money     = xPlayer.player.money,
			accounts  = xPlayer.accounts,
			inventory = xPlayer.inventory
		}

		TriggerClientEvent('esx:responsePlayerDataForGUI', _source, data)

	end)
end)

RegisterServerEvent('esx:requestLastPosition')
AddEventHandler('esx:requestLastPosition', function()
	
	local _source = source

	TriggerEvent('esx:getPlayerFromId', source, function(xPlayer)
		
		local executed_query  = MySQL:executeQuery("SELECT * FROM users WHERE identifier = '@identifier'", {['@identifier'] = xPlayer.identifier})
		local result          = MySQL:getResults(executed_query, {'position'})

		local position = nil

		if result[1].position ~= nil then
			position = json.decode(result[1].position)
		end

		TriggerClientEvent('esx:responseLastPosition', _source, position)

	end)
end)


RegisterServerEvent('esx:registerUsableItem')
AddEventHandler('esx:registerUsableItem', function(item, cb)
	UsableItemsCallbacks[item] = cb
end)

RegisterServerEvent('esx:useItem')
AddEventHandler('esx:useItem', function(item)
	UsableItemsCallbacks[item](source)
end)

RegisterServerEvent('esx:removeInventoryItem')
AddEventHandler('esx:removeInventoryItem', function(item, count)
	
	local _source = source

	if count == nil or count <= 0 then
		TriggerClientEvent('esx:showNotification', _source, 'Quantité ~r~invalide~s~')
	else

		TriggerEvent('esx:getPlayerFromId', source, function(xPlayer)

			local foundItem = nil

			for i=1, #xPlayer.inventory, 1 do
				if xPlayer.inventory[i].item == item then
					foundItem = xPlayer.inventory[i]
				end
			end

			if count > foundItem.count then
				TriggerClientEvent('esx:showNotification', _source, '~r~Quantité invalide~s~')
			else
				
				TriggerClientEvent('esx:showNotification', _source, '~r~Suppression~s~ dans 5 minutes')
				
				SetTimeout(Config.RemoveInventoryItemDelay, function()
					
					local remainingCount = xPlayer:getInventoryItem(item).count
					local total          = count

					if remainingCount < count then
						total = remainingCount
					end
					
					if total > 0 then
						xPlayer:removeInventoryItem(item, total)
						TriggerClientEvent('esx:showNotification', _source, 'Vous avez ~r~jeté~s~ ' .. foundItem.label .. ' x' .. total)
					end

				end)

			end

		end)

	end

end)

RegisterServerEvent('esx:removeCash')
AddEventHandler('esx:removeCash', function(amount)
	
	local _source = source

	TriggerEvent('esx:getPlayerFromId', _source, function(xPlayer)

		if xPlayer.player.money >= amount then

			TriggerClientEvent('esx:showNotification', _source, '~r~Suppression~s~ dans 5 minutes')

			SetTimeout(Config.RemoveInventoryItemDelay, function()
				
				local remainingCount = xPlayer.player.money
				local total          = amount

				if remainingCount < amount then
					total = remainingCount
				end
				
				if total > 0 then
					xPlayer:removeMoney(total)
					TriggerClientEvent('esx:showNotification', _source, 'Vous avez ~r~jeté~s~ ~r~$' .. total)
				end

			end)

		else
			TriggerClientEvent('esx:showNotification',  _source, 'Montant ~r~invalide~s~')
		end

	end)

end)

RegisterServerEvent('esx:removeAccountMoney')
AddEventHandler('esx:removeAccountMoney', function(accountName, amount)
	
	local _source = source

	TriggerEvent('esx:getPlayerFromId', _source, function(xPlayer)

		local account = xPlayer:getAccount(accountName)

		if account.money >= amount then

			TriggerClientEvent('esx:showNotification', _source, '~r~Suppression~s~ dans 5 minutes')

			SetTimeout(Config.RemoveInventoryItemDelay, function()
				
				local remainingCount = account.money
				local total          = amount

				if remainingCount < amount then
					total = remainingCount
				end
				
				if total > 0 then
					xPlayer:removeAccountMoney(accountName, total)
					TriggerClientEvent('esx:showNotification', _source, 'Vous avez ~r~jeté~s~ ~r~$' .. total)
				end

			end)

		else
			TriggerClientEvent('esx:showNotification', _source, 'Montant ~r~invalide~s~')
		end
		
	end)

end)

RegisterServerEvent('esx:giveItem')
AddEventHandler('esx:giveItem', function(playerId, itemName, count)
	
	local _source = source

	TriggerEvent('esx:getPlayerFromId', _source, function(sourceXPlayer)

		local sourceItem = sourceXPlayer:getInventoryItem(itemName)

		if count > 0 and sourceItem.count >= count then

			TriggerEvent('esx:getPlayerFromId', playerId, function(targetXPlayer)
				
				local targetItem = targetXPlayer:getInventoryItem(itemName)

				if targetItem.limit ~= -1 and (targetItem.count + sourceItem.count) > targetItem.limit then
					TriggerClientEvent('esx:showNotification', _source, 'Quantité ~r~invalide~s~, dépassement de limite d\'inventaire pour la cible')
				else
					
					sourceXPlayer:removeInventoryItem(itemName, count)
					targetXPlayer:addInventoryItem(itemName, count)

					TriggerClientEvent('esx:showNotification', _source, 'Vous avez donné x' .. count .. ' ' .. Items[itemName].label)
					TriggerClientEvent('esx:showNotification', playerId, 'Vous avez reçu x' .. count .. ' ' .. Items[itemName].label)
				end
			end)
		else
			TriggerClientEvent('esx:showNotification', _source, 'Quantité ~r~invalide~s~')
		end

	end)

end)

RegisterServerEvent('esx:giveCash')
AddEventHandler('esx:giveCash', function(playerId, amount)
	
	local _source = source

	TriggerEvent('esx:getPlayerFromId', _source, function(xPlayer)

		local money = xPlayer.player.money

		if amount > 0 and money >= amount then

			xPlayer:removeMoney(amount)

			TriggerEvent('esx:getPlayerFromId', playerId, function(targetXPlayer)
				
				targetXPlayer:addMoney(amount)
				
				TriggerClientEvent('esx:showNotification', _source, 'Vous avez ~r~envoyé~s~ ~r~$' .. amount)
				TriggerClientEvent('esx:showNotification', playerId, 'Vous avez ~g~reçu~s~ ~g~$' .. amount)
			end)
			
		else
			TriggerClientEvent('esx:showNotification', _source, 'Montant ~r~invalide~s~')
		end

	end)

end)

RegisterServerEvent('esx:giveAccountMoney')
AddEventHandler('esx:giveAccountMoney', function(playerId, accountName, amount)
	
	local _source = source

	TriggerEvent('esx:getPlayerFromId', _source, function(xPlayer)

		local account = xPlayer:getAccount(accountName)

		if amount > 0 and account.money >= amount then

			xPlayer:removeAccountMoney(accountName, amount)

			TriggerEvent('esx:getPlayerFromId', playerId, function(targetXPlayer)
				
				targetXPlayer:addAccountMoney(accountName, amount)
				
				TriggerClientEvent('esx:showNotification', _source, 'Vous avez ~r~envoyé~s~ ~r~$' .. amount)
				TriggerClientEvent('esx:showNotification', playerId, 'Vous avez ~g~reçu~s~ ~g~$' .. amount)
			end)
			
		else
			TriggerClientEvent('esx:showNotification', _source, 'Montant ~r~invalide~s~')
		end

	end)

end)

RegisterServerEvent('esx:requestPlayerPositions')
AddEventHandler('esx:requestPlayerPositions', function(reason)
	
	local _source = source

	TriggerEvent('esx:getPlayers', function(xPlayers)

		local positions = {}

		for k, v in pairs(xPlayers) do
			positions[tostring(k)] = v.player.coords
		end

		TriggerClientEvent('esx:responsePlayerPositions', _source, positions, reason)

	end)

end)

TriggerEvent("es:addGroup", "jobmaster", "user", function(group) end)

TriggerEvent('es:addGroupCommand', 'tp', 'admin', function(source, args, user)

	TriggerClientEvent("esx:teleport", source, {
		x = tonumber(args[2]),
		y = tonumber(args[3]),
		z = tonumber(args[4])
	})

end, function(source, args, user)
	TriggerClientEvent('chatMessage', source, "SYSTEM", {255, 0, 0}, "Insufficient Permissions.")
end)

TriggerEvent('es:addGroupCommand', 'loadipl', 'admin', function(source, args, user)
	TriggerClientEvent('esx:loadIPL', -1, args[2])
end, function(source, args, user)
	TriggerClientEvent('chatMessage', source, "SYSTEM", {255, 0, 0}, "Insufficient Permissions.")
end)

TriggerEvent('es:addGroupCommand', 'unloadipl', 'admin', function(source, args, user)
	TriggerClientEvent('esx:unloadIPL', -1, args[2])
end, function(source, args, user)
	TriggerClientEvent('chatMessage', source, "SYSTEM", {255, 0, 0}, "Insufficient Permissions.")
end)

TriggerEvent('es:addGroupCommand', 'setjob', 'jobmaster', function(source, args, user)
	TriggerEvent('esx:getPlayerFromId', tonumber(args[2]), function(xPlayer)
		xPlayer:setJob(args[3], tonumber(args[4]))
	end)
end, function(source, args, user)
	TriggerClientEvent('chatMessage', source, "SYSTEM", {255, 0, 0}, "Insufficient Permissions.")
end)

TriggerEvent('es:addCommand', 'sendmoney', function(source, args, user)

	local targetId = tonumber(args[2])
	local amount   = tonumber(args[3])

	if amount == nil or amount <= 0 or amount > user.money then

		TriggerClientEvent('chatMessage', source, 'MONEY', {255, 0, 0}, 'Montant ~r~invalide~s~')

	else

		TriggerClientEvent('chatMessage', source, 'MONEY', {255, 255, 0}, ' (^2' .. GetPlayerName(source) .. ' | '..source..'^0) ' .. table.concat(args, ' '))

		TriggerEvent('es:getPlayerFromId', source, function(user)
			TriggerEvent('es:getPlayerFromId', targetId, function(targetUser)
				
				if targetUser == nil then

					TriggerClientEvent('chatMessage', source, 'MONEY', {255, 0, 0}, '~r~Aucun~s~ joueur trouvé ayant l\'id ' .. targetId)

				else

					if targetId == source then

						TriggerClientEvent('chatMessage', source, 'MONEY', {255, 0, 0}, 'Vous ~r~ne pouvez pas vous envoyer~s~ de l\'argent à vous-même')

					else

						local userName       = GetPlayerName(source  )
						local targetUserName = GetPlayerName(targetId)

						user:removeMoney(amount)
						targetUser:addMoney(amount)

						TriggerClientEvent('chatMessage', source,   'MONEY', {255, 255, 0}, 'Vous avez ~r~envoyé~s~ ~r~€~s~' .. args[3] .. ' à ' .. targetUserName)
						TriggerClientEvent('chatMessage', targetId, 'MONEY', {255, 255, 0}, userName .. ' vous a ~r~envoyé~s~ ~r~€~s~' .. args[3])
					
					end
				end

			end)
		end)

	end

end)

local data = {}

local function saveData()
	
	SetTimeout(60000, function()
		
		local query     = ''
		local userCount = 0

		for k,v in pairs(Users)do
			
			local source = v.player.source

			if data[source] == nil then
				
				data[source] = {
					accounts  = {},
					inventory = {}
				}

				for i=1, #v.accounts, 1 do
					table.insert(data[source].accounts, {
						name  = v.accounts[i].name,
						money = nil
					})
				end

				for i=1, #v.inventory, 1 do
					table.insert(data[source].inventory, {
						item  = v.inventory[i].item,
						count = nil
					})
				end

			end

			-- User accounts
			local subQuery  = ''
			local itemCount = 0

			for i=1, #v.accounts, 1 do

				if v.accounts[i].money ~= data[source].accounts[i].money then
					
					subQuery = subQuery .. "UPDATE user_accounts SET `money`='" .. v.accounts[i].money .. "' WHERE identifier = '" .. v.identifier .. "' AND name = '" .. v.accounts[i].name .. "';"
					itemCount = itemCount + 1

					for i=1, #v.accounts, 1 do
						data[source].accounts[i] = {
							name  = v.accounts[i].name,
							money = v.accounts[i].money
						}
					end

				end

			end

			if itemCount > 0 then
				query = query .. subQuery
			end

			-- Inventory items
			local subQuery  = ''
			local itemCount = 0

			for i=1, #v.inventory, 1 do

				if v.inventory[i].count ~= data[source].inventory[i].count then

					subQuery  = subQuery .. "UPDATE user_inventory SET `count`='" .. v.inventory[i].count .. "' WHERE identifier = '" .. v.identifier .. "' AND item = '" .. v.inventory[i].item .. "';"
					itemCount = itemCount + 1

					for i=1, #v.inventory, 1 do
						data[source].inventory[i] = {
							item  = v.inventory[i].item,
							count = v.inventory[i].count
						}
					end

				end

			end

			if itemCount > 0 then
				query = query .. subQuery
			end

			-- Job, loadout and position
			query = query .. "UPDATE users SET job = '" .. v.job.name .. "', job_grade = '" .. v.job.grade .. "', loadout = '" .. json.encode(v.loadout) .. "', position='" .. json.encode(v.player.coords) .. "' WHERE identifier = '" .. v.identifier .. "';"

			userCount = userCount + 1
		end

		if userCount > 0 then
			MySQL:executeQuery(query)
		end

		saveData()

	end)
end

saveData()

AddEventHandler('playerDropped', function()
	data[source] = nil
end)

local function paycheck()

	SetTimeout(Config.PaycheckInterval, function()

		TriggerEvent('esx:getPlayers', function(players)

			for k,v in pairs(players) do
				v:addMoney(v.job.grade_salary)
				TriggerClientEvent('esx:showNotification', v.player.source, 'Vous avez reçu votre salaire : ' .. '~g~$' .. v.job.grade_salary)
			end

		end)

		paycheck()

	end)
end

paycheck()