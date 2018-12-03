local sock, err = ngx.socket.tcp()

if err then
	-- log
else
	sock:settimeout(5000)
	local ok, err = sock:connect('127.0.0.1',13370)  -- nc -l 13370 开启一个 TCP server
	local bytes, err = sock:send('paprikaLang')
	ngx.say(bytes)
end