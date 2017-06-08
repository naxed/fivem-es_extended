require "resources/[essential]/es_extended/lib/MySQL"
MySQL:open("127.0.0.1", "gta5_gamemode_essential", "root", "foo")

Users                = {}
UsableItemsCallbacks = {}
Items                = {}

local executed_query = MySQL:executeQuery("SELECT * FROM items")
local result         = MySQL:getResults(executed_query, {'name', 'label', 'limit'})

for i=1, #result, 1 do
	Items[result[i].name] = {
		label = result[i].label,
		limit = result[i].limit
	}
end