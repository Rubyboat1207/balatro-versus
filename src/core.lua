local socket = require("socket")
local json = require("json")

VSMOD_GLOBALS = {}
VSMOD_GLOBALS.FUNCS = {}

VSMOD_GLOBALS.FUNCS.vs_connect = function()
        local ip = VSMOD_GLOBALS.ip_address
        -- Pass the socket handling logic to the thread
        tcp_recv = "local ip = ...\n function giveMeJSON()" .. json.literally_the_entire_library_as_a_string .. "\nend\n" .. [[
        local json = giveMeJSON()
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
    ]]

    love.thread.newThread(tcp_recv):start(ip)
end

function vsmod_update()
    if VSMOD_GLOBALS.client then
        -- Check for received data
        if love.thread.getChannel('tcp_recv'):peek() then
            local data = love.thread.getChannel('tcp_recv'):pop()
            print("Got Data: " .. data)
            local decoded = json.decode(data)
            if decoded.type == "update_score" then
                local score_data = json.decode(decoded.data)
                VSMOD_GLOBALS.opponent_chips = score_data.score
            end
        end
    end
end

function initVersusMod()
    VSMOD_GLOBALS.ip_address = ""
    VSMOD_GLOBALS.opponent_chips = 0
end

function makeMultiplayerTab()
    return {n=G.UIT.ROOT, config={align = "cm", padding = 0.05, colour = G.C.CLEAR}, nodes={
        create_text_input({
            max_length = 15,
            extended_corpus = true,
            all_caps = false,
            ref_table = VSMOD_GLOBALS,
            ref_value = 'ip_address',
            prompt_text = "Versus Opponent IP",
        }),
        UIBox_button{button = "vs_connect", colour = G.C.BLUE, minw = 2.65, minh = 1.35, label = {"Connect"}, scale = 2.4, col = true} or nil
    }}
end

function onHandScored(hand_score)
    if VSMOD_GLOBALS.client then
        local sendChannel = love.thread.getChannel('tcp_send')
        sendChannel:push(json.encode({type = "on_score", data = json.encode({score = G.GAME.chips + hand_score})}))
    end
end

function getOpponentScoreUI()
    return {
        n = G.UIT.R,
        config = { align = "cm", r = 0.1, padding = 0, colour = G.C.DYN_UI.BOSS_MAIN, emboss = 0.05, id = 'row_dollars_chips' },
        nodes = {
            {
                n = G.UIT.C,
                config = { align = "cm", padding = 0.1 },
                nodes = {
                    {
                        n = G.UIT.C,
                        config = { align = "cm", minw = 1.3 },
                        nodes = {
                            {
                                n = G.UIT.R,
                                config = { align = "cm", padding = 0, maxw = 1.3 },
                                nodes = {
                                    { n = G.UIT.T, config = { text = "Opp.", scale = 0.42, colour = G.C.UI.TEXT_LIGHT, shadow = true } }
                                }
                            },
                            {
                                n = G.UIT.R,
                                config = { align = "cm", padding = 0, maxw = 1.3 },
                                nodes = {
                                    { n = G.UIT.T, config = { text = localize('k_lower_score'), scale = 0.42, colour = G.C.UI.TEXT_LIGHT, shadow = true } }
                                }
                            }
                        }
                    },
                    {
                        n = G.UIT.C,
                        config = { align = "cm", minw = 3.3, minh = 0.7, r = 0.1, colour = G.C.DYN_UI.BOSS_DARK },
                        nodes = {
                            { n = G.UIT.O, config = { w = 0.5, h = 0.5, object = get_stake_sprite(G.GAME.stake or 1, 0.5), hover = true, can_collide = false } },
                            { n = G.UIT.B, config = { w = 0.1, h = 0.1 } },
                            {
                                n = G.UIT.T,
                                config = {
                                    ref_table = VSMOD_GLOBALS,
                                    ref_value = 'opponent_chips',
                                    lang = G.LANGUAGES['en-us'],
                                    scale = 0.85,
                                    colour = G.C.WHITE,
                                    id = 'chip_UI_count',
                                    func = 'chip_UI_set',
                                    shadow = true
                                }
                            }
                        }
                    }
                }
            }
        }
    }
end
