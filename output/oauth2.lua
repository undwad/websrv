
require 'std'
require 'websrv'
require "https"
local url = require "url"
local ltn12 = require "ltn12"
local json = require 'json'
require 'utf8'

function string:replace(map)
    local result = self
    for what,with in pairs(map) do
        local i = result:find(what)
        if nil ~= i then 
            result = result:sub(0, i - 1)..with..result:sub(i + what:len()) 
        end
    end
    return result
end

function getNestedValue(object, ...)
    local args = {...}
    if #args > 0 and object[args[1]] then
        object = object[args[1]]
        table.remove(args, 1)
        if object and #args > 0 then 
            return getNestedValue(object, table.unpack(args)) 
        end
        return object
    end
    return nil
end

local oauth2 =
{
    access_token_body_pattern = 'code={CODE}&client_id={CLIENT_ID}&client_secret={CLIENT_SECRET}&redirect_uri={REDIRECT_URI}&grant_type=authorization_code',
    redirect_uri = 'http://zalupa.org/oauth2/',
    services = 
    {
        yandex =
        {
            enabled = true,
            href_pattern = 'https://oauth.yandex.ru/authorize?response_type=code&client_id={CLIENT_ID}&state={STATE}',
            client_id = 'd2f8ddcb159d4da1b26987c686e98409',
            client_secret = 'be22fb5f63ec451caf505020cf42527e',
            access_token_uri = 'https://oauth.yandex.ru/token',
            info_uri_pattern = 'https://login.yandex.ru/info?format=json&oauth_token={ACCESS_TOKEN}'
        },
        google =
        {
            enabled = true,
            href_pattern = 'https://accounts.google.com/o/oauth2/auth?redirect_uri={REDIRECT_URI}&response_type=code&client_id={CLIENT_ID}&scope=email&state={STATE}',
            client_id = '1003457679327-3fpgd7gjo6okmscll44nu0ho9t1090gq@developer.gserviceaccount.com',
            client_secret = 'rtRe6ygLpn5IhtowxIxDus4Q',
            access_token_uri = 'https://accounts.google.com/o/oauth2/token',
        },
        ['mail.ru'] =
        {
            enabled = true,
            href_pattern = 'https://connect.mail.ru/oauth/authorize?client_id={CLIENT_ID}&redirect_uri={REDIRECT_URI}&response_type=code&state={STATE}',
            client_id = '727652',
            client_secret = '8d7779e54bee723dadc22ce4fc00bb57',
            access_token_uri = 'https://connect.mail.ru/oauth/token',
        },
        facebook =
        {
            enabled = false,
            href_pattern = 'https://www.facebook.com/dialog/oauth?client_id={CLIENT_ID}&redirect_uri={REDIRECT_URI}&response_type=code&state={STATE}',
            client_id = '740409662718765',
            client_secret = 'f8df3185f4c62b719a8acbaffe1d8d26',
            access_token_uri = 'https://accounts.google.com/o/oauth2/token',
        }
    }
}

local server = websrv.server.init{port = 80, file = 'f:/github/websrv/output/test.log'}

local function return_error(session, code, text)
    websrv.client.HTTPdirective('HTTP/1.1 '..code..' '..text)
    session.write('Content-type: text/html\r\n\r\n')
    session.write('\n')
    session.write(text)
    session.write('\n\n')        
end

websrv.server.addhandler{server = server, mstr = '*/', func = function(session)
	session.write 'Content-type: text/html\r\n\r\n'
    session.write '<HTML><BODY bgcolor="EFEFEF"><form>'
    for service, params in pairs(oauth2.services) do
        if params.enabled then
            local href = string.replace(params.href_pattern, {
                ['{REDIRECT_URI}'] = url.escape(oauth2.redirect_uri..service), 
                ['{CLIENT_ID}'] = params.client_id,
                ['{STATE}'] = 'JODER',
            })
            session.write('<a href="'..href..'" title="enter via '..service..'">enter via '..service..'</a><br/>')
        end
    end
    session.write '</form>'
end}

websrv.server.addhandler{server = server, mstr = '*/oauth2/*', func = function(session)
    local path = url.parse_path(session.request)
    local service = path[#path]
    local state = session.Query("state")
    local code = session.Query("code")
    if oauth2.services[service] and string.len(state) > 0 and string.len(code) > 0 then
        if 'JODER' == state then
            local params = oauth2.services[service]

            local body = string.replace(params.access_token_body_pattern or oauth2.access_token_body_pattern, {
                ['{REDIRECT_URI}'] = url.escape(oauth2.redirect_uri..service), 
                ['{CLIENT_ID}'] = params.client_id,
                ['{CODE}'] = url.escape(code),
                ['{CLIENT_SECRET}'] = params.client_secret,
            })
            
            local res, code, headers, status = ssl.https.request(params.access_token_uri, body)
            session.write 'Content-type: text/plain\r\n\r\n'
            session.write('res: '..res..'\n\n')
            session.write('code: '..code..'\n\n')
            session.write('headers: '..headers..'\n\n')
            session.write('status: '..status..'\n\n')
            session.write('url: '..params.access_token_uri..'\n\n')
            session.write('body: '..body..'\n\n')
            
            --[[
            local response = {}
            local b, c, h, d = http.request
            {
                url = params.access_token_uri,
                method = 'POST',
                headers = 
                {
                    ['content-type'] = 'application/x-www-form-urlencoded',
                    ['content-length'] = body:len()
                },
                source = ltn12.source.string(body),
                sink = ltn12.sink.table(response) 
            }
            
            local s,e = pcall(function()
                local result = json:decode(response[1] or '{error_description: "invalid response"}')
                if 200 == c then
                    session.write 'Content-type: text/plain\r\n\r\n'
                    session.write(tostring(result)..'\n')
                    --local url = string.replace(params.info_uri_pattern, { ['{ACCESS_TOKEN}'] = result.access_token })
                    --session.write(url..'\n')
                    --local info = http.request(url)
                    --session.write('INFO: ', tostring(info)..'\n')
                else return_error(session, c, result.error_description) end
            end)
            if not s then
                session.write 'Content-type: text/plain\r\n\r\n'
                session.write(code..'\n\n')
                session.write(params.access_token_uri..'\n\n')
                session.write(e..'\n\n')
            end
            --]]
        else return_error(session, 401, 'Unauthorized') end
    else return_error(session, 400, 'Bad Request') end
end}

websrv.server.addhandler{server = server, mstr = '*/receiver.html', func = function(session)
    session.write("Content-type: text/html\r\n\r\n")
    local f = io.open('f:/github/websrv/output/receiver.html ', "r")
    session.write(f:read("*all"))
    f:close()
end}

while true do
	websrv.server.run(server)
end