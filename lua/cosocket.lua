local sock, err = ngx.socket.tcp()

if err then
	-- log
else
	sock:settimeout(5000)
	local ok, err = sock:connect('127.0.0.1',13370)  -- nc -l 13370 开启一个 TCP server/ telnet 127.0.0.1 13370客户端连接
	local bytes, err = sock:send('paprikaLang')
	ngx.say(bytes)
end