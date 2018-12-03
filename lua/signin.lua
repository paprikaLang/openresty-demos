local cjson = require "cjson.safe"

local db = require "lua.db"

ngx.req.read_body()
local data = ngx.req.get_body_data()
if data then
	local user = cjson.decode(data)
	local username, password = user.username, user.password;
	if username == nil then
		ngx.say("please input username")
		ngx.eof()
	end
	if password == nil then
		ngx.say("please input password")
		ngx.eof()
	end
	db.insertUser({ username = username, password = password })
	ngx.say(data)
	return
end

