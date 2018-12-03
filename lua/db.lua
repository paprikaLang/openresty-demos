local cjson = require "cjson.safe"
local db = {}

function db.getUsers()		
	local data = ngx.shared.db:get("users")
	if data == nil then
		data = "[]"
	end

	local users = cjson.decode(data)
	return users
end

function db.hasUser( user )
	local users = db.getUsers()
	for _, _user in ipairs(users) do
		if _user.username == user.username then
			return true
		end
	end
	return false
end

function db.insertUser( user )
	local users = db.getUsers()
	if db.hasUser(user) then
		return
	end
	table.insert(users, user)
	ngx.shared.db:set("users", cjson.encode(users))
end

return db