local redis = require "resty.redis"
local red = redis:new()

red:set_timeout(1000)

local ok, err = red:connect("127.0.0.1",6379)
if not ok then 
	ngx.say("failed to connect: ",err)
	return
end
-- 第一次连接Redis要认证, 后面再链接则在连接池获取Redis 重用次数不为零不用再次验证
local count 
count, err = red:get_reused_times()
if 0 == count then
	ok, err = red:auth("password")
	if not ok then
		ngx.say("failed to auth: ", err)
		return
	end
elseif err then
	ngx.say("failed to get reused times: ", err)
end

-- 
ok, err = red:set("dog", "paki")
if not ok then 
	ngx.say("failed to set dog: ", err)
	return
end

ngx.say("set result: ", ok)

local res, err = red:get("dog")
if not res then
	ngx.say("failed to get dog: ",err)
	return
end

if res == ngx.null then
	ngx.say("dog not found.")
	return
end
ngx.say("dog: ", res)

-- commit时候一次发送所有的set,get指令到Redis执行
red:init_pipeline()
red:set("cat","marry")
red:set("horse","bob")
red:get("cat")
red:get("horse")
local results, err = red:commit_pipeline()
if not results then
	 ngx.say("failed to commit the pipelined requests: ",err)
	 return
end

for i, res in ipairs(results) do
	if type(res) == "table" then
		if res[1] == false then
			ngx.say("failed to run command ", i, ": ",res[2])
		else
			-- process the table value
		end
	else
		-- process the scalar value
	end
end
-- cosocket提供长连接 复用连接--> 连接池size:100; 10秒 max idle time
local ok, err = red:set_keepalive(10000, 100)
if not ok then
	ngx.say("failed to set keepalive: ", err)
	return
end
