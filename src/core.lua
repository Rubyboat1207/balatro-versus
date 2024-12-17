local socket = require("socket")
local json = require("json")

VSMOD_GLOBALS = {
    SCORES = {}
}
VSMOD_GLOBALS.FUNCS = {}

VSMOD_GLOBALS.FUNCS.vs_connect = function()
    local ip = VSMOD_GLOBALS.ip_address
    -- Pass the socket handling logic to the thread
    tcp_recv = "local ip, id = ...\n function giveMeJSON()" .. json.literally_the_entire_library_as_a_string .. "\nend\n" .. [[
        local json = giveMeJSON()
        local socket = require("socket")

        if ip == "" then
            return
        end
        local tcp = socket.tcp()
        tcp:settimeout(3)
        local printoutChannel = love.thread.getChannel('tcp_printout')

        local success, err = tcp:connect(ip, 5304)
        if not success then
            printoutChannel:push("Failed to connect to " .. ip .. ": " .. err)
            return
        end
        tcp:settimeout(5)
        local sendChannel = love.thread.getChannel('tcp_send')
        local recvChannel = love.thread.getChannel('tcp_recv')
        local signalChannel = love.thread.getChannel('tcp_signal')
        printoutChannel:push("Connected to " .. ip)

        while true do
            -- Handle incoming messages
            local data, status = tcp:receive("*l")
            printoutChannel:push(data)
            if status == "closed" then
                return
            end
            if data then
                recvChannel:push(data)
            end

            -- Handle outgoing messages
            msg = sendChannel:pop()
            if msg then
                printoutChannel:push('sending message')
                tcp:send(msg)
            end

            socket.sleep(0.01)
        end
    ]]
    
    love.thread.getChannel('tcp_signal'):push(VSMOD_GLOBALS.tcp_id)
    love.thread.newThread(tcp_recv):start(ip, VSMOD_GLOBALS.tcp_id)
    VSMOD_GLOBALS.tcp_id = VSMOD_GLOBALS.tcp_id + 1
end

function vsmod_round_ended(game_over)
    local sendChannel = love.thread.getChannel('tcp_send')
    sendChannel:push(json.encode({type = "update_score", data = json.encode({score = 0, blind = G.GAME.round + G.GAME.skips + 1})}))
    sendChannel:push(json.encode({type = "blind_cleared", data = json.encode({blind=G.GAME.round + G.GAME.skips})}))
    VSMOD_GLOBALS.opponent_chips = VSMOD_GLOBALS.SCORES[G.GAME.round + G.GAME.skips + 1] or 0
    VSMOD_GLOBALS.started_remotely = nil
end

function vsmod_run_start()
    if VSMOD_GLOBALS.started_remotely and G.STATE ~= 11 then
        return
    end
    VSMOD_GLOBALS.SCORES = {}
    local sendChannel = love.thread.getChannel('tcp_send')
    sendChannel:push(json.encode({type = "start_game", data = json.encode({seed = G.GAME.pseudorandom.seed, stake = G.GAME.stake})}))
end

function vsmod_update()
    -- Check for received data
    local data = love.thread.getChannel('tcp_recv'):pop()
    if data then
        print("Got Data: " .. data)
        local decoded = json.decode(data)
        if decoded.type == "update_score" then
            local score_data = json.decode(decoded.data)
            VSMOD_GLOBALS.SCORES[score_data.blind] = score_data.score
            VSMOD_GLOBALS.opponent_chips = VSMOD_GLOBALS.SCORES[G.GAME.round + G.GAME.skips] or 0
        elseif decoded.type == "start_game" then
            VSMOD_GLOBALS.started_remotely = true
            local game_data = json.decode(decoded.data)
            G.FUNCS.start_run(nil, {stake = game_data.stake, seed = game_data.seed, challenge = nil})
            VSMOD_GLOBALS.SCORES = {}
        elseif decoded.type == "declare_winner" then
            local winning_data = json.decode(decoded.data)

            if winning_data.won then
                if winning_data.prize_type == 'gain_money' then
                    local val = json.decode(winning_data.prize_value)

                    ease_dollars(val, false)
                end
                print("You won blind " .. winning_data.blind)
            else
                print("You lost blind " .. winning_data.blind)
            end

        end
    end
    local pr = love.thread.getChannel('tcp_printout'):pop()

    if pr then
        print('THREADED: ' .. pr)
    end
end

function initVersusMod()
    VSMOD_GLOBALS.ip_address = "localhost"
    VSMOD_GLOBALS.opponent_chips = 0
    VSMOD_GLOBALS.tcp_id = 0
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
    local sendChannel = love.thread.getChannel('tcp_send')
    sendChannel:push(json.encode({type = "update_score", data = json.encode({score = G.GAME.chips + hand_score, blind = G.GAME.round + G.GAME.skips})}))
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
