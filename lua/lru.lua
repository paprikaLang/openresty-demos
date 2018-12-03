local shared = ngx.shared['db']  -- 获取申请的共享内存

local suc, err, forc

for index=1, 10000,1 do
	suc, err, forc = shared:set(tostring(index), string.rep('a', 1))
end

-- local keys = shared:get_keys()
local keys = shared:get_keys(0)  -- 8095
ngx.say(#keys) -- 1024 lua_shared_dict db 1m;

local value, flag = shared:get('1') -- nil
local value, flag = shared:get('10000')  -- a
ngx.say(forc)  -- true
ngx.say(value)
suc, err, forc = shared:set('foo', string.rep('a', 1000))
ngx.say(err) -- no memory
-- 当剔除第一位的内存之后仍无法满足本次的需求就会返回no memory 的报错

for index=1, 10000,1 do
	suc, err, forc = shared:set(tostring(index), string.rep('a', 56))
	-- suc, err, forc = shared:set(tostring(index), string.rep('a', 57))
end
local keys = shared:get_keys(0)  
ngx.say(#keys) -- 8095 --4032 减半  slab


-- 缓存失效风暴
-- 1. return cache
-- 2. 锁 block 阻塞请求
-- 3. 允许一个请求访问这个缓存, 失败
-- 4.进入第四步, 向上游服务器获取缓存 并解开锁
-- 阻塞的请求重新访问这个缓存

