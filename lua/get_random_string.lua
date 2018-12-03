local args = ngx.req.get_uri_args()
local salt = args.salt
if not salt then
    ngx.exit(ngx.HTTP_BAD_REQUEST)
end

local string = ngx.md5(ngx.time() .. salt)
ngx.say(string)
-- ngx-lua api 是非阻塞的   lua的API是阻塞的