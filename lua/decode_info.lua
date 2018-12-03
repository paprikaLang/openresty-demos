local json = require "cjson"
-- curl -i  http://127.0.0.1/decode_info --data "info=cGFwcmlrYUxhbmc="
ngx.req.read_body()
local args = ngx.req.get_post_args()

if not args or not args.info then
	ngx.exit(ngx.HTTP_BAD_REQUEST)
end

local client_ip = ngx.var.remote_addr
local user_agent = ngx.req.get_headers()['user_agent'] or ''
local info = ngx.decode_base64(args.info)

local response = {}
response.info = info 
response.ip =  client_ip
response.user_agent = user_agent
-- {"info":"paprikaLang","ip":"127.0.0.1","user_agent":"curl\/7.54.0"}
ngx.say(json.encode(response))