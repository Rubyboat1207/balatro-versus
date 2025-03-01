local json = require "json"

VSMOD_GLOBALS = {
    SCORES = {},
    VERSUS = false,
    last_on_blind = {},
    connection_state = {
        connected = false,
        awaiting_connect = false,
        just_connected = false,
        queued_connection_ip = nil,
        queued_connection_lobby = nil
    },
    CARD_EFFECTS = {},
    REWARDS = {},
    imp_card = {},
    JOKERS = {},
    CONSUMABLES = {},
    HEARTBEAT_TIMER = 15,
    TIME_SINCE_HEARTBEAT = 0,
    VICTORY_NOTIFICATION = nil,
    VISUAL_OPPONENT_SCORE = ""
}
VSMOD_GLOBALS.FUNCS = {}

local function connect()
    NFS.write("vsmod_config.json", json.encode({ ip_address = VSMOD_GLOBALS.ip_address }))
    VSMOD_GLOBALS.HEARTBEAT_TIMER = 15
    VSMOD_GLOBALS.TIME_SINCE_HEARTBEAT = 0

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
        signalChannel:push("connected")

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

local function update_mp_tab()
    if G.OVERLAY_MENU then
        local tab_contents = G.OVERLAY_MENU:get_UIE_by_ID('tab_contents')
        local mp_tab = G.OVERLAY_MENU:get_UIE_by_ID('mp_tab_content')
        if tab_contents and mp_tab then
            tab_contents.config.object:remove()
            tab_contents.config.object = UIBox{
                definition = G.UIDEF.settings_tab("Multiplayer"),
                config = {offset = {x=0,y=0}, parent = tab_contents, type = 'cm'}
            }
            tab_contents.UIBox:recalculate()
        end
    end
end

local function monitor_connection()
    local signal = love.thread.getChannel('tcp_signal')
    local sendChannel = love.thread.getChannel('tcp_send')
    local dt = love.timer.getDelta( )

    local latest_signal = signal:peek()
    local cs = VSMOD_GLOBALS.connection_state

    if cs.connected then
        if VSMOD_GLOBALS.HEARTBEAT_TIMER > 0 then
            VSMOD_GLOBALS.HEARTBEAT_TIMER = VSMOD_GLOBALS.HEARTBEAT_TIMER - dt
        else
            VSMOD_GLOBALS.HEARTBEAT_TIMER = 0
        end

        if VSMOD_GLOBALS.HEARTBEAT_TIMER == 0 then
            if VSMOD_GLOBALS.TIME_SINCE_HEARTBEAT == 0 then
                sendChannel:push(json.encode({
                    type = "heartbeat"
                }))
                print('sent heartbeat')
            end

            VSMOD_GLOBALS.TIME_SINCE_HEARTBEAT = VSMOD_GLOBALS.TIME_SINCE_HEARTBEAT + dt
            if VSMOD_GLOBALS.TIME_SINCE_HEARTBEAT > 30 then
                print('connection didnt respond to the heartbeat fast enough. disconnecting')
                signal:push('disconnect')
            end
        end
    elseif cs.queued_connection_ip then
        VSMOD_GLOBALS.ip_address = cs.queued_connection_ip
        cs.queued_connection_ip = nil
        connect()
    end
    

    if latest_signal == "disconnected" then
        print('old connection successfully disconnected')
        signal:pop()
        cs.connected = false
        VSMOD_GLOBALS.in_lobby = false
        update_mp_tab()
    end

    if VSMOD_GLOBALS.connection_state.just_connected then
        VSMOD_GLOBALS.connection_state.just_connected = false
        update_mp_tab()
    end

    if latest_signal == "connected" then
        VSMOD_GLOBALS.connection_state.just_connected = true
        if cs.queued_connection_lobby then
            VSMOD_GLOBALS.lobby_id = cs.queued_connection_lobby
            cs.queued_connection_lobby = nil
            VSMOD_GLOBALS.FUNCS.vs_joinlobby()
        end
        signal:pop()
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

function VSMOD_GLOBALS.FUNCS.vs_disconnect(e)
    love.thread.getChannel('tcp_recv'):clear()
    local signal = love.thread.getChannel('tcp_signal')
    signal:clear()

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

    G.STEAM.friends.setRichPresence("connect", VSMOD_GLOBALS.ip_address .. "|" .. VSMOD_GLOBALS.lobby_id)
end

function runVictoryNotification(won, itemName, round)

    local atlas_x = 0
    if won then
        atlas_x = 1
    end
    VSMOD_GLOBALS.VICTORY_NOTIFICATION = UIBox {
        definition = create_UiBox_victory_notification(round, won, VSMOD_GLOBALS.ICONS, {x=atlas_x,y=0}, itemName, won),
        config = {align='cr', offset = {x=8, y=0.5},major = G.ROOM_ATTACH, bond = 'Weak'}
    }
    G.E_MANAGER:add_event(Event({
        trigger = "ease",
        blocking=false,
        delay = 1,
        ref_table = VSMOD_GLOBALS.VICTORY_NOTIFICATION.alignment.offset,
        ref_value = "x",
        ease_to = -2,
    }))
    G.E_MANAGER:add_event(Event({
        trigger = "after",
        blocking=false,
        delay = 10,
        func = function ()
            G.E_MANAGER:add_event(Event({
                trigger = "ease",
                blocking = true,
                delay = 1,
                ref_table = VSMOD_GLOBALS.VICTORY_NOTIFICATION.alignment.offset,
                ref_value = "x",
                ease_to = 8,
            }))
            return true
        end
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

function VSMOD_GLOBALS.REWARDS.create_card(data, won)
    local set = G.P_CENTERS[data.card].set
    runVictoryNotification(won, "a " .. localize({type = "name_text", key = G.P_CENTERS[data.card].key, set = set} ), G.GAME.round + G.GAME.skips)
    if not won then
        return
    end
    local area
    if set == "Joker" then
        area = G.jokers
        G.GAME.joker_buffer = G.GAME.joker_buffer + 1
    else
        area = G.consumeables
        G.GAME.consumeable_buffer = G.GAME.consumeable_buffer + 1
    end
    G.GAME.joker_buffer = G.GAME.joker_buffer + 1
    G.E_MANAGER:add_event(Event({
        func = function()
            local _T = G.jokers.T

            local card = Card(_T.x, _T.y, G.CARD_W, G.CARD_H, G.P_CARDS.empty, G.P_CENTERS[data.card] ,{discover = true, bypass_discovery_center = true, bypass_discovery_ui = true, bypass_back = G.GAME.selected_back.pos })
            if data.perishable then
                card:set_perishable(true)
            end
            if data.edition then
                card:set_edition(data.edition, true)
            end
            card:add_to_deck()
            area:emplace(card)
            card:start_materialize()
            if cardType == "Joker" then
                G.GAME.joker_buffer = G.GAME.joker_buffer - 1
            else
                G.GAME.consumeable_buffer = G.GAME.consumeable_buffer - 1
            end
            return true
        end
    }))
end

function VSMOD_GLOBALS.REWARDS.random_card(data, won)
    -- todo: maybe send all of the registered cards to the server so that the server picks one at random instead of the client.
    -- then we could tell the other clients what card was picked and they could put it in the notification.
    runVictoryNotification(won, "a random card.", G.GAME.round + G.GAME.skips)
    if not won then
        return
    end

    area = nil
    if data.card_type == "Joker" then
        area = G.jokers
        G.GAME.joker_buffer = G.GAME.joker_buffer + 1
    else
        area = G.consumeables
        G.GAME.consumeable_buffer = G.GAME.consumeable_buffer + 1
    end

    
    G.E_MANAGER:add_event(Event({
        func = function()
            local card = create_card(data.card_type, area, nil, data.rarity or nil, nil, nil, nil, 'pri')
            card:add_to_deck()
            if data.card_type == "Joker" then
                G.jokers:emplace(card)
                card:start_materialize()
                G.GAME.joker_buffer = G.GAME.joker_buffer - 1
            else
                G.consumeables:emplace(card)
                G.GAME.consumeable_buffer = G.GAME.consumeable_buffer - 1
            end
            return true
        end
    }))
end

function VSMOD_GLOBALS.REWARDS.gain_money(data, won)
    runVictoryNotification(won, "$" .. data, G.GAME.round + G.GAME.skips)
    if not won then
        return
    end
    ease_dollars(data, false)
end

function VSMOD_GLOBALS.CARD_EFFECTS.flip(card)
    card:flip()
end

function VSMOD_GLOBALS.CARD_EFFECTS.force_select(card)
    card.ability.forced_selection = true
    G.hand:add_to_highlighted(card)
end

function VSMOD_GLOBALS.CARD_EFFECTS.reset_edition(card)
    card.ability.forced_selection = true
    card:set_edition({ }, true)
end

function vsmod_update()
    local pr = love.thread.getChannel('tcp_printout'):pop()

    if pr then
        print('THREADED: ' .. pr)
    end
    -- Check for received data
    monitor_connection()

    if G.STATE > 3 and G.STATE ~= 8 then
        VSMOD_GLOBALS.opponent_chips = 0
        VSMOD_GLOBALS.VISUAL_OPPONENT_SCORE = "0"
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
            local used_saved_game = false
            if G.SAVED_GAME ~= nil then
                print("saved game exists")
                print(json.encode(G.SAVED_GAME))
                if G.SAVED_GAME.GAME.stake == game_data.stake then
                    print("Stake matches: " .. G.SAVED_GAME.GAME.stake)
                else
                    print("Stake does not match: " .. G.SAVED_GAME.GAME.stake .. " vs " .. game_data.stake)
                end
                if G.SAVED_GAME.GAME.pseudorandom.seed == game_data.seed then
                    print("Seed matches: " .. G.SAVED_GAME.GAME.pseudorandom.seed)
                else
                    print("Seed does not match: " .. G.SAVED_GAME.GAME.pseudorandom.seed .. " vs " .. game_data.seed)
                end
                if G.SAVED_GAME.BACK.name == game_data.deck then
                    print("Deck matches: " .. G.SAVED_GAME.BACK.name)
                else
                    print("Deck does not match: " .. G.SAVED_GAME.BACK.name .. " vs " .. game_data.deck)
                end

                if G.SAVED_GAME.GAME.stake == game_data.stake and G.SAVED_GAME.GAME.pseudorandom.seed == game_data.seed and G.SAVED_GAME.BACK.name == game_data.deck then
                    G:start_run({savetext = G.SAVED_GAME})
                    used_saved_game = true
                end
            end
            if not used_saved_game then
                G.GAME.viewed_back = get_deck_from_name(game_data.deck)
                G.GAME.selected_back = G.GAME.viewed_back
                G.FUNCS.start_run(nil, { stake = game_data.stake, seed = game_data.seed, challenge = nil })
                G.GAME.seeded = false
                VSMOD_GLOBALS.SCORES = {}
            end
        elseif decoded.type == "declare_winner" then
            local winning_data = json.decode(decoded.data)
            VSMOD_GLOBALS.REWARDS[winning_data.prize_type](json.decode(winning_data.prize_value), winning_data.won)
        elseif decoded.type == "game_normal" then
            love.thread.getChannel('tcp_signal'):push('disconnect')
        elseif decoded.type == "last_on_blind" then
            VSMOD_GLOBALS.last_on_blind["" .. json.decode(decoded.data)] = true
        elseif decoded.type == "hand_effect" then
            if G.STATE >= 3 then
                return
            end
            
            local data = json.decode(decoded.data)
            local is_single_card = false
            local valid_cards = {}
            local card_area = nil
            if data.area == "hand" then
                card_area = G.hand.cards
            elseif data.area == "jokers" then
                card_area = G.jokers.cards
            end
            
            for k, v in ipairs(card_area or {}) do
                if data.selector == "random" or data.selector == "all" then
                    valid_cards[#valid_cards+1] = v
                end
                if data.selector == "half" then
                    if k % 2 == 0 then
                        valid_cards[#valid_cards+1] = v
                    end
                end
                if data.selector == "random_with_edition" then
                    if v.edition and not v.edition.negative then
                        valid_cards[#valid_cards+1] = v
                    end
                end
            end
            
            local card = nil
            
            if data.selector == "random" or data.selector == "random_with_edition" then
                is_single_card = true
                card = pseudorandom_element(valid_cards, pseudoseed('select-' .. G.GAME.round_resets.ante .. data.effect .. G.GAME.round))
            end
            
            
            if data.selector == "all" or data.selector == "half" then
                card = valid_cards
            end

            if not is_single_card then
                for _, selected_card in ipairs(card) do
                    VSMOD_GLOBALS.CARD_EFFECTS[data.effect](selected_card)
                end
            else
                VSMOD_GLOBALS.CARD_EFFECTS[data.effect](card)
            end
        elseif decoded.type == 'heartbeat' then
            VSMOD_GLOBALS.HEARTBEAT_TIMER = 15
            VSMOD_GLOBALS.TIME_SINCE_HEARTBEAT = 0
        elseif decoded.type == 'lobby_joined' then
            VSMOD_GLOBALS.in_lobby = true
        elseif decoded.type == 'hand_type_effect' then
            local data = json.decode(decoded.data)
            local hand = nil
            if data.selector == 'highest' then
                hand = G.GAME.current_round.most_played_poker_hand or "Flush"
            elseif data.selector == 'recent' then
                hand = G.GAME.last_hand_played or "Flush"
            end

            if data.effect == 'level' then
                local level = data.modifier or 1
                update_hand_text({immediate = true, nopulse = true, delay = 0}, {mult = 0, chips = 0, level = '', handname = hand})
                level_up_hand(nil, hand, false, level)
            end
        end
    end
end

function vsmod_should_end_round()
    if
        not VSMOD_GLOBALS.in_lobby or
        (
            VSMOD_GLOBALS.last_on_blind["" .. G.GAME.round + G.GAME.skips] and VSMOD_GLOBALS.SCORES["" .. G.GAME.round + G.GAME.skips] and
            G.GAME.chips > VSMOD_GLOBALS.SCORES["" .. G.GAME.round + G.GAME.skips]
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
    G.E_MANAGER:add_event(Event({
        trigger = "immediate",
        func = function()
            NFS.write("centers_data.json", json.encode(G.P_CENTERS))
            if G.STEAM then
                NFS.write("steam_data.json", json.encode(G.STEAM))

                function G.STEAM.friends.onGameRichPresenceJoinRequested(data)
                    local connection_string = data.connect
                    local split_data = {}
                    for part in string.gmatch(connection_string, "([^|]+)") do
                        table.insert(split_data, part)
                    end
                    VSMOD_GLOBALS.connection_state.queued_connection_ip = split_data[1]
                    VSMOD_GLOBALS.connection_state.queued_connection_lobby = split_data[2]
                end
            end
            return true
        end
    }))
    
end



function create_UiBox_victory_notification(roundNumber, didWin, spriteAtlas, spritePos, itemName, isPlayer)
    -- Determine the primary and secondary text
    local mainText = didWin and ("You won round " .. roundNumber) or ("You lost round " .. roundNumber)
    local subText  = isPlayer and ("You got \n" .. itemName) or ("An opponent got \n" .. itemName)
  
    -- Create a sprite with your defined atlas/position
    local t_s = Sprite(
      0, 
      0, 
      1.5 * (spriteAtlas.px / spriteAtlas.py), -- Adjust scaling as needed
      1.5,
      spriteAtlas, 
      spritePos
    )
    -- Disable sprite interactivity
    t_s.states.drag.can    = false
    t_s.states.hover.can   = false
    t_s.states.collide.can = false

    text_color = G.C.UI_MULT
    if not didWin then
      text_color = G.C.UI_MULT
    end
  
    -- Build the UI table (UIT) structure
    local t = {
      n = G.UIT.ROOT,
      config = {
        align  = 'tr',
        r      = 0.1,
        padding= 0.06,
        colour = G.C.UI.TRANSPARENT_DARK
      },
      nodes = {
        {
          n = G.UIT.R,
          config = {
            align          = "tr",
            padding        = 0.2,
            w              = 0.4,
            minh           = 3,
            r              = 0.1,
            colour         = G.C.BLACK,
            outline        = 1.5,
            outline_colour = G.C.GREY
          },
          nodes = {
            {
              n = G.UIT.R,
              config = {
                align = "cm",
                r     = 0.1
              },
              nodes = {
                -- Sprite container
                {
                  n = G.UIT.R,
                  config = {
                    align = "cm",
                    r     = 0.1
                  },
                  nodes = {
                    {
                      n = G.UIT.O,
                      config = {
                        object = t_s
                      }
                    }
                  }
                },
                -- Text container
                {
                  n = G.UIT.R,
                  config = {
                    align   = "cm",
                    padding = 0.04
                  },
                  nodes = {
                    {
                      n = G.UIT.R,
                      config = {
                        align = "cm",
                        maxw  = 1.4
                      },
                      nodes = {
                        {
                          n = G.UIT.T,
                          config = {
                            text   = mainText,
                            scale  = 0.5,
                            colour = G.C.FILTER,
                            shadow = true
                          }
                        }
                      }
                    },
                    {
                      n = G.UIT.R,
                      config = {
                        align = "cm",
                        maxw  = 3.4
                      },
                      nodes = {
                        {
                          n = G.UIT.T,
                          config = {
                            text   = subText,
                            scale  = 0.2,
                            colour = G.C.FILTER,
                            shadow = true,
                            w = 0.5
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  
    return t
  end
  

function makeMultiplayerTab()
    local ptext = "Versus Opponent IP"
    local ref_val = "ip_address"
    local label_txt = "Connect To Server"
    local fn = "vs_connect"
    local disconnect_button = nil

    if VSMOD_GLOBALS.connection_state.connected then
        ptext = "Lobby Id"
        ref_val = "lobby_id"
        label_txt = "Join Lobby"
        fn = "vs_joinlobby"
        disconnect_button = UIBox_button { button = "vs_disconnect", colour = G.C.RED, minw = 2.65, minh = 1.35, label = { "Disconnect" }, scale = 1.2, col = true }
    end
    local btn = UIBox_button { button = fn, colour = G.C.BLUE, minw = 2.65, minh = 1.35, label = { label_txt }, scale = 1.2, col = true }
    return {
        n = G.UIT.ROOT,
        config = { align = "cm", padding = 0.05, colour = G.C.CLEAR, id = 'mp_tab_content' },
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
                            btn,
                            disconnect_button
                        }
                    }
                }
            }
        }
    }
end

G.FUNCS.opp_chip_UI_set = function(e)
    local new_chips_text = number_format(VSMOD_GLOBALS.opponent_chips)
    if G.GAME.chips_text ~= new_chips_text then
        e.config.scale = math.min(0.8, scale_number(VSMOD_GLOBALS.opponent_chips, 1.1))
        VSMOD_GLOBALS.VISUAL_OPPONENT_SCORE = new_chips_text
    end
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
    -- VSMOD_GLOBALS.REWARDS.create_card({card = "c_versus_square"}, true)
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
                                    ref_value = 'VISUAL_OPPONENT_SCORE',
                                    lang = G.LANGUAGES['en-us'],
                                    scale = 0.85,
                                    colour = G.C.WHITE,
                                    id = 'opp_chip_UI_count',
                                    func = 'opp_chip_UI_set',
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

function vsmod_drawVictoryNotif()
    if VSMOD_GLOBALS.VICTORY_NOTIFICATION then
        love.graphics.push()
            VSMOD_GLOBALS.VICTORY_NOTIFICATION:translate_container()
            VSMOD_GLOBALS.VICTORY_NOTIFICATION:draw()
        love.graphics.pop()
    end
end

SMODS.Atlas {
    key = "VersusJokers",
    path = "jokers.png",
    px = 69,
    py = 93
}

SMODS.Atlas {
    key = "VersusConsumables",
    path = "tarot.png",
    px = 63,
    py = 93
}

SMODS.Atlas {
    key = "VersusPlanets",
    path = "planets.png",
    px = 63,
    py = 93
}

VSMOD_GLOBALS.ICONS = SMODS.Atlas {
    key = "VersusIcons",
    path = "icons.png",
    px = 64,
    py = 64
}

VSMOD_GLOBALS.JOKERS.ghoulish_imp = SMODS.Joker {
    key = "ghoulish_imp",
    set = "Joker",
    loc_txt = {
        name = "Ghoulish Imp",
        text = {
            "for each hand with a {C:attention}#1#{} played",
            "cause any player currently playing a blind to",
            "have a card force selected",
            "card changes every round",
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
                        type = "ability_used",
                        data = json.encode({
                            ability = "force_select_single"
                        })
                    }))

                    print("skill issue")
                
                    return {
                        message = "curse",
                        colour = G.C.MULT,
                        card = card
                    }
                end
            end
        end
    end
}

VSMOD_GLOBALS.CONSUMABLES.mask = SMODS.Consumable({
    set = "Tarot",
    key = "mask",
    pos = {
        x = 0,
        y = 0
    },
    loc_txt = {
        name = "Mask",
        text = {
            "For all opponents",
            "every other card is flipped over",
            "for current hand"
        }
    },
    atlas = 'VersusConsumables',
    cost = 2,
    discovered = true,
    can_use = function() return true end,
    use = function() 
        love.thread.getChannel('tcp_send'):push(json.encode({
            type = "ability_used",
            data = json.encode({
                ability = "flip_half"
            })
        }))
    end
})

local SquareOfDeathOdds = 4

VSMOD_GLOBALS.CONSUMABLES.square = SMODS.Consumable({
    set = "Tarot",
    key = "square",
    pos = {
        x = 1,
        y = 0
    },
    loc_txt = {
        name = "Square of Death",
        text = {
            "{C:green}#1# in #2#{} chance to remove",
            "{C:dark_edition}Foil{}, {C:dark_edition}Holographic{}, or",
            "{C:dark_edition}Polychrome{} edition from",
            "one of all opponents' jokers."
        }
    },
    loc_vars = function(self, info_queue, card)
        return { vars = { G.GAME.probabilities.normal, SquareOfDeathOdds } }
    end,
    atlas = 'VersusConsumables',
    cost = 1,
    discovered = true,
    can_use = function(self) return true end,
    use = function(self, card, area, copier)
        if pseudorandom('Square of Death') < G.GAME.probabilities.normal/SquareOfDeathOdds then
            love.thread.getChannel('tcp_send'):push(json.encode({
                type = "ability_used",
                data = json.encode({
                    ability = "remove_edition"
                })
            }))
        else
            attention_text({
                text = localize('k_nope_ex'),
                scale = 1.3, 
                hold = 1.4,
                major = card or copier,
                backdrop_colour = G.C.SECONDARY_SET.Tarot,
                align = (G.STATE == G.STATES.TAROT_PACK or G.STATE == G.STATES.SPECTRAL_PACK) and 'tm' or 'cm',
                offset = {x = 0, y = (G.STATE == G.STATES.TAROT_PACK or G.STATE == G.STATES.SPECTRAL_PACK) and -0.2 or 0},
                silent = true
            }) 
        end
    end
})

VSMOD_GLOBALS.CONSUMABLES.europa = SMODS.Consumable({
    set = "Planet",
    key = "europa",
    pos = {
        x = 0,
        y = 0
    },
    loc_txt = {
        name = "Europa",
        text = {
            "Levels down the most played hand",
            "of your opponents",
        }
    },
    atlas = 'VersusPlanets',
    cost = 3,
    discovered = true,
    can_use = function() return true end,
    use = function() 
        love.thread.getChannel('tcp_send'):push(json.encode({
            type = "ability_used",
            data = json.encode({
                ability = "down_level_hand"
            })
        }))
    end
})

initVersusMod()