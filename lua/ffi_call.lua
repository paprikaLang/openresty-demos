local ffi = require("ffi")
ffi.cdef[[
int printf(const char *fmt, ...);
]]

ffi.C.printf("Hello %s!", "World\n")

-- /usr/local/Cellar/openresty/1.13.6.2/luajit/bin/luajit-2.1.0-beta3 
-- /usr/local/Cellar/openresty/1.13.6.2/nginx/lua/ffi_call.lua