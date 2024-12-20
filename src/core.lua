local socket = require "socket"
local json = require "json"
local lovely = require "lovely"

VSMOD_GLOBALS = {
    SCORES = {},
    VERSUS = false,
    last_on_blind = {},
    connection_state = {
        connected = false,
        awaiting_connect = false
    },
    REWARDS = {},
    imp_card = {},
    JOKERS = {}
}
VSMOD_GLOBALS.FUNCS = {}

local function connect()
    if NFS.read("vsmod_config.json") == nil then
        NFS.write("vsmod_config.json", json.encode({ ip_address = VSMOD_GLOBALS.ip_address }))
    end

    tcp_recv = "local ip= ...\n function giveMeJSON()" ..
        json.literally_the_entire_library_as_a_string .. "\nend\n" .. [[
        local json = giveMeJSON()
        local socket = require("socket")
        local signalChannel = love.thread.getChannel('tcp_signal')

        if ip == "" then
            signalChannel:push("disconnected")
            return
        end
        local tcp = socket.tcp()
        tcp:settimeout(3)
        local printoutChannel = love.thread.getChannel('tcp_printout')

        local success, err = tcp:connect(ip, 5304)
        if not success then
            printoutChannel:push("Failed to connect to " .. ip .. ": " .. err)
            signalChannel:push("disconnected")
            return
        end
        tcp:settimeout(0)
        local sendChannel = love.thread.getChannel('tcp_send')
        local recvChannel = love.thread.getChannel('tcp_recv')
        printoutChannel:push("Connected to " .. ip)

        while true do
            -- Handle incoming messages
            local data, status = tcp:receive("*l")
            if data then
                printoutChannel:push(data)
            end
            if status == "closed" then
                break
            end
            if data then
                printoutChannel:push('recieved message ' .. data:gsub('%"', "'"))
                recvChannel:push(data)
            end

            -- Handle outgoing messages
            msg = sendChannel:pop()
            if msg then
                printoutChannel:push('sending message ' .. msg:gsub('%"', "'"))
                tcp:send(msg)
            end

            local signal = signalChannel:peek()

            if signal == "disconnect" then
                signalChannel:pop()
                tcp:close()
                break
            end

            socket.sleep(0.01)
        end
        signalChannel:push("disconnected")
    ]]

    love.thread.newThread(tcp_recv):start(VSMOD_GLOBALS.ip_address)
end

local function monitor_connection()
    local signal = love.thread.getChannel('tcp_signal')

    local latest_signal = signal:peek()
    local cs = VSMOD_GLOBALS.connection_state

    if latest_signal == "disconnected" then
        print('old connection successfully disconnected, making new connection')
        signal:pop()
        cs.connected = false
    end

    if cs.awaiting_connect and cs.connected == false then
        print("No connection exists, creating new one!")
        cs.awaiting_connect = false
        cs.connected = true
        connect()
    end
end

function VSMOD_GLOBALS.FUNCS.vs_connect()
    VSMOD_GLOBALS.normal_mode = false
    love.thread.getChannel('tcp_recv'):clear()
    love.thread.getChannel('tcp_send'):clear()
    local signal = love.thread.getChannel('tcp_signal')
    signal:clear()

    print("attempting connection.")
    VSMOD_GLOBALS.connection_state.awaiting_connect = true

    if VSMOD_GLOBALS.connection_state.connected then
        print("old connection exists, pushing disconnect signal")
        VSMOD_GLOBALS.connection_state.awaiting_disconnect = true
        signal:push('disconnect')
    end

end

function VSMOD_GLOBALS.FUNCS.vs_joinlobby()
    if VSMOD_GLOBALS.lobby_id == "" then
        return
    end
    print('attempting to join lobby')
    love.thread.getChannel('tcp_send'):push(json.encode({
        type = "join_lobby",
        data = json.encode({
            lobby_id = VSMOD_GLOBALS.lobby_id
        })
    }))
end

function vsmod_round_ended(game_over)
    local sendChannel = love.thread.getChannel('tcp_send')
    sendChannel:push(json.encode({
        type = "update_score",
        data = json.encode({
            score = 0,
            blind = G.GAME.round +
                G.GAME.skips + 1
        })
    }))
    sendChannel:push(json.encode({
        type = "blind_cleared",
        data = json.encode({
            blind = G.GAME.round + G.GAME.skips,
            game_over =
                game_over
        })
    }))
    VSMOD_GLOBALS.started_remotely = nil
    VSMOD_GLOBALS.imp_card = update_imp_card()
end

function update_imp_card()
    local card = {
        rank = "Ace"
    }
    local valid_cards = {}
    for k, v in ipairs(G.playing_cards) do
        if v.ability.effect ~= 'Stone Card' then
            valid_cards[#valid_cards+1] = v
        end
    end
    if valid_cards[1] then 
        local imp_card = pseudorandom_element(valid_cards, pseudoseed('imp'..G.GAME.round_resets.ante))
        card.rank = imp_card.base.value
        card.id = imp_card.base.id
    end
    return card
end

function vsmod_run_start()
    VSMOD_GLOBALS.SCORES = {}
    VSMOD_GLOBALS.imp_card = update_imp_card()
    local sendChannel = love.thread.getChannel('tcp_send')
    sendChannel:push(json.encode({
        type = "start_game",
        data = json.encode({
            seed = G.GAME.pseudorandom.seed,
            stake = G
                .GAME.stake,
            deck = G.GAME.selected_back.name
        })
    }))

end

function VSMOD_GLOBALS.REWARDS.random_joker(data)
    G.GAME.joker_buffer = G.GAME.joker_buffer + 1
    G.E_MANAGER:add_event(Event({
        func = function()
            local card = create_card('Joker', G.jokers, nil, data, nil, nil, nil, 'pri')
            card:set_perishable(true)
            card:set_edition({ negative = true }, true)
            card:add_to_deck()
            G.jokers:emplace(card)
            card:start_materialize()
            G.GAME.joker_buffer = G.GAME.joker_buffer - 1
            return true
        end
    }))
end

function VSMOD_GLOBALS.REWARDS.create_joker(data) 
    G.GAME.joker_buffer = G.GAME.joker_buffer + 1
    G.E_MANAGER:add_event(Event({
        func = function()
            joker = nil
            if data.modded then
                joker = VSMOD_GLOBALS.JOKERS[data.joker]
            else
                joker = find_joker(data.joker)
            end

            if not joker then
                return
            end
            local _T = G.jokers.T

            local card = Card(_T.x, _T.y, G.CARD_W, G.CARD_H, G.P_CARDS.empty, joker ,{discover = true, bypass_discovery_center = true, bypass_discovery_ui = true, bypass_back = G.GAME.selected_back.pos })
            card:set_perishable(true)
            card:set_edition({ negative = true }, true)
            card:add_to_deck()
            G.jokers:emplace(card)
            card:start_materialize()
            G.GAME.joker_buffer = G.GAME.joker_buffer - 1
            return true
        end
    }))
end

function VSMOD_GLOBALS.REWARDS.random_consumable(data)
    G.GAME.consumeable_buffer = G.GAME.consumeable_buffer + 1
    G.E_MANAGER:add_event(Event({
        func = function()
            local card = create_card(data, G.consumeables, nil, nil, nil, nil, nil, 'pri')
            card:add_to_deck()
            G.consumeables:emplace(card)
            G.GAME.consumeable_buffer = G.GAME.consumeable_buffer - 1
            return true
        end
    }))
end

function VSMOD_GLOBALS.REWARDS.gain_money(data)
    ease_dollars(data, false)
end

function vsmod_update()
    local pr = love.thread.getChannel('tcp_printout'):pop()

    if pr then
        print('THREADED: ' .. pr)
    end
    -- Check for received data
    monitor_connection()

    if G.STATE >= 3 and G.STATE ~= 8 then
        VSMOD_GLOBALS.opponent_chips = 0
    else
        VSMOD_GLOBALS.opponent_chips = VSMOD_GLOBALS.SCORES[G.GAME.round + G.GAME.skips] or 0
    end

    local data = love.thread.getChannel('tcp_recv'):pop()
    if data then
        local decoded = json.decode(data)
        if decoded.type == "update_score" then
            local score_data = json.decode(decoded.data)
            if score_data.score > (VSMOD_GLOBALS.SCORES[score_data.blind] or 0) then
                VSMOD_GLOBALS.SCORES[score_data.blind] = score_data.score
            end
        elseif decoded.type == "start_game" then
            local game_data = json.decode(decoded.data)
            G.GAME.viewed_back = get_deck_from_name(game_data.deck)
            G.GAME.selected_back = G.GAME.viewed_back
            G.FUNCS.start_run(nil, { stake = game_data.stake, seed = game_data.seed, challenge = nil })
            G.GAME.seeded = false
            VSMOD_GLOBALS.SCORES = {}
        elseif decoded.type == "declare_winner" then
            local winning_data = json.decode(decoded.data)
            if winning_data.won then
                VSMOD_GLOBALS.REWARDS[winning_data.prize_type](json.decode(winning_data.prize_value))
                print("You won blind " .. winning_data.blind)
            else
                print("You lost blind " .. winning_data.blind)
            end
        elseif decoded.type == "game_normal" then
            love.thread.getChannel('tcp_signal'):push('disconnect')
        elseif decoded.type == "last_on_blind" then
            VSMOD_GLOBALS.last_on_blind[json.decode(decoded.data)] = true
        elseif decoded.type == "hand_effect" then
            if G.STATE >= 3 then
                return
            end
            local data = json.decode(decoded.data)
            
            local valid_cards = {}

            for k, v in ipairs(G.hand.cards) do
                if data.selector == "random" then
                    valid_cards[#valid_cards+1] = v
                end
            end
            
            card = nil

            if data.selector == "random" then
                card = pseudorandom_element(valid_cards, pseudoseed('select'))
            end
            
            if data.effect == "force_select" then
                G.hand:unhighlight_all()
                card.ability.forced_selection = true
                G.hand:add_to_highlighted(card)
            end
        end
    end
end

function vsmod_should_end_round()
    if
        not VSMOD_GLOBALS.connection_state.connected or
        (
            VSMOD_GLOBALS.last_on_blind["" .. G.GAME.round + G.GAME.skips] and
            G.GAME.chips > VSMOD_GLOBALS.SCORES[G.GAME.round + G.GAME.skips]
        )
    then
        return G.GAME.chips - G.GAME.blind.chips >= 0 or G.GAME.current_round.hands_left < 1
    end

    if VSMOD_GLOBALS.round_cleared_at == nil and G.GAME.chips - G.GAME.blind.chips >= 0 then
        VSMOD_GLOBALS.round_cleared_at = G.GAME.current_round.hands_left
    end
    if G.GAME.current_round.hands_left < 1 then
        if G.GAME.chips - G.GAME.blind.chips >= 0 then
            G.GAME.current_round.hands_left = VSMOD_GLOBALS.round_cleared_at
            VSMOD_GLOBALS.round_cleared_at = nil
        end
        return true
    end
    return false
end

function initVersusMod()
    VSMOD_GLOBALS.ip_address = ""
    VSMOD_GLOBALS.lobby_id = ""
    VSMOD_GLOBALS.opponent_chips = 0
    VSMOD_GLOBALS.normal_mode = true

    local config = NFS.read("vsmod_config.json")

    if config then
        local decoded = json.decode(config)
        if decoded.ip_address then
            VSMOD_GLOBALS.ip_address = decoded.ip_address
        end
    end

    VSMOD_GLOBALS.FUNCS.vs_connect()
end

function makeMultiplayerTab()
    local ptext = "Versus Opponent IP"
    local ref_val = "ip_address"
    local label_txt = "Connect To Server"
    local fn = "vs_connect"

    if VSMOD_GLOBALS.connection_state.connected then
        ptext = "Lobby Id"
        ref_val = "lobby_id"
        label_txt = "Join Lobby"
        fn = "vs_joinlobby"
    end
    return {
        n = G.UIT.ROOT,
        config = { align = "cm", padding = 0.05, colour = G.C.CLEAR },
        nodes = {
            {
                n = G.UIT.C,
                config = { align = "tm", colour = G.C.CLEAR },
                nodes = {
                    {
                        n = G.UIT.R,
                        config = { align = "cm" },
                        id = 'ip',
                        nodes = {
                            create_text_input({
                                max_length = 15,
                                extended_corpus = true,
                                all_caps = false,
                                ref_table = VSMOD_GLOBALS,
                                ref_value = ref_val,
                                prompt_text = ptext,
                            }),
                            UIBox_button { button = fn, colour = G.C.BLUE, minw = 2.65, minh = 1.35, label = { label_txt }, scale = 1.2, col = true } or
                            nil,
                        }
                    }
                }
            }
        }
    }
end

function onHandScored(hand_score)
    local sendChannel = love.thread.getChannel('tcp_send')
    sendChannel:push(json.encode({
        type = "update_score",
        data = json.encode({
            score = G.GAME.chips + hand_score,
            blind =
                G.GAME.round + G.GAME.skips
        })
    }))
end

function getOpponentScoreUI()
    if VSMOD_GLOBALS.normal_mode then
        return {
            n = G.UIT.R,
        }
    end
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

SMODS.Atlas {
    key = "VersusJokers",
    path = "jokers.png",
    px = 69,
    py = 93
}

VSMOD_GLOBALS.JOKERS.ghoulish_imp = SMODS.Joker {
    key = "ghoulish_imp",
    loc_txt = {
        name = "Ghoulish Imp",
        text = {
            "for each hand with a {C:attention}#1#{} played",
            "cause any player currently playing a blind to",
            "have a card force selected",
            "changes every round",
        }
    },
    rarity = 3,
    loc_vars = function(self, info_queue, card)
        return { vars = { VSMOD_GLOBALS.imp_card.rank } }
    end,
    atlas = "VersusJokers",
    cost = 3,
    yes_pool_flag = 'never',
    calculate = function(self, card, context)
        if context.cardarea == G.jokers and context.before then
            for _, v in ipairs(context.scoring_hand) do
                if v:get_id() == VSMOD_GLOBALS.imp_card.id then
                    love.thread.getChannel('tcp_send'):push(json.encode({
                        type = "multiplayer_joker_ability",
                        data = json.encode({
                            joker = "ghoulish_imp"
                        })
                    }))
                
                    return {
                        message = "curse",
                        colour = G.C.MULT,
                        card = self
                    }
                end
            end
        end
    end
}

initVersusMod()