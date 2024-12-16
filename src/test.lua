
local json = giveMeJSON()
local ip = ...
local socket = require("socket")


if ip == "" then
    return
end
local client = socket.tcp()
client:settimeout(1)

local success, err = client:connect(ip, 5304)
if not success then
    print("Failed to connect to " .. ip .. ": " .. err)
    return
end
print("Connected to " .. ip)

local sendChannel = love.thread.getChannel('tcp_send')
local recvChannel = love.thread.getChannel('tcp_recv')

while true do
    -- Handle incoming messages
    local data, msg = client:receive()
    if data then
        recvChannel:push(data)
    end

    -- Handle outgoing messages
    if sendChannel:peek() then
        local message = sendChannel:pop()
        client:send(message)
    end
end