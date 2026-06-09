minetest.register_privilege("binds", {
    description = "gives access to the functions playertrue, tick",
    give_to_singleplayer = false,
})

local _click_lockout = {}
local _bind_cooldowns = {}

minetest.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    _click_lockout[name] = nil
    for k, _ in pairs(_bind_cooldowns) do
        if k:sub(1, #name + 1) == name .. "_" then
            _bind_cooldowns[k] = nil
        end
    end
end)

local function run_bind_command(executing_player_name, creator_name, cmd_name, param, playertrue)
    if not minetest.chatcommands or type(minetest.chatcommands) ~= "table" then
        return false
    end

    local creator_privs = minetest.get_player_privs(creator_name)
    local creator_has_bind_priv = creator_privs.binds

    if executing_player_name ~= creator_name then
        if not (playertrue and creator_has_bind_priv) then
            minetest.chat_send_player(executing_player_name, "You cannot use this bind.")
            return false
        end
    end

    local command_def = minetest.chatcommands[cmd_name]
    if not command_def then
        minetest.chat_send_player(executing_player_name, "Error /" .. cmd_name .. " Invalid command")
        return false
    end

    local has_privs = minetest.check_player_privs(executing_player_name, command_def.privs or {})
    if has_privs then
        command_def.func(executing_player_name, param or "")
        return true
    else
        minetest.chat_send_player(executing_player_name, "[Error] Not Enough Privilege to run /" .. cmd_name)
        return false
    end
end

minetest.register_chatcommand("bind", {
    params = "[reloading] [disposable: 0/1] [tick] <cmd> [playertrue]",
    description = "Bind cmd to any item.",
    func = function(name, param)
        local player = minetest.get_player_by_name(name)
        if not player then return false end
        
        local stack = player:get_wielded_item()
        local item_name = stack:get_name()
        if item_name == "" then return false, "Take the Item in Hand" end
        if param == "" then return false, "Usage: /bind [reloading] [disposable: 0/1] [tick] <cmd> [playertrue]" end

        local player_privs = minetest.get_player_privs(name)
        local has_bind_priv = player_privs.binds

        local playertrue = false
        if param:match("%s+playertrue$") then
            if not has_bind_priv then
                return false, "You don't have the binds privilege for the playertrue task"
            end
            playertrue = true
            param = param:gsub("%s+playertrue$", "")
        end

        local cooldown = 3
        local once = false
        local cooldown_raw, once_raw, rest_param = param:match("^(%d+)%s+(%d+)%s+(.+)$")
        if cooldown_raw and once_raw and rest_param then
            cooldown = math.max(0, tonumber(cooldown_raw))
            once = (tonumber(once_raw) == 1)
            param = rest_param
        end

        local is_tick = false
        if param:match("^tick%s+") then
            if not has_bind_priv then
                return false, "You don't have the Binds privilege for tick"
            end
            is_tick = true
            param = param:gsub("^tick%s+", "")
        elseif param == "tick" then
            return false, "Usage: /bind [reloading] [disposable: 0/1] tick <cmd>"
        end
        
        local cmd_name, cmd_param = param:match("^([^%s]+)%s*(.*)$")
        cmd_name = cmd_name or param
        if cmd_name:sub(1, 1) == "/" then cmd_name = cmd_name:sub(2) end
        
        if cmd_name == "bind" or cmd_name == "unbind" or cmd_name == "bindlist" then
            return false, "You cannot bind this command."
        end
        
        if not minetest.chatcommands[cmd_name] then
            return false, "to /" .. cmd_name .. " Invalid command"
        end
        
        if cmd_param then
            cmd_param = cmd_param:gsub("[%c]", "") 
        end
        
        local uuid = tostring(math.random(100000, 999999)) .. "_" .. tostring(minetest.get_gametime())

        local bind_data = {
            cmd = cmd_name,
            param = cmd_param or "",
            cooldown = cooldown,
            once = once, 
            is_tick = is_tick,
            creator = name,
            uuid = uuid,
            playertrue = playertrue
        }
        
        local meta = stack:get_meta()
        meta:set_string("item_bind", minetest.serialize(bind_data))
        player:set_wielded_item(stack)
        
        local mode_str = once and " [Disposable]" or " [Reusable]"
        local p_str = playertrue and " [Global]" or " [Private]"
        return true, "bind created /" .. cmd_name .. " | Reloading: " .. cooldown .. "sec." .. mode_str .. (is_tick and " [TICK]" or "") .. p_str
    end,
})

minetest.register_chatcommand("unbind", {
    description = "Removes the bind of an item in your hand.",
    func = function(name)
        local player = minetest.get_player_by_name(name)
        if not player then return false end
        local stack = player:get_wielded_item()
        if stack:get_name() == "" then return false, "Take the Item in Hand" end
        local meta = stack:get_meta()
        meta:set_string("item_bind", "")
        player:set_wielded_item(stack)
        return true, "Bind Removed"
    end,
})

minetest.register_chatcommand("bindlist", {
    description = "Show active binds.",
    func = function(name)
        local player = minetest.get_player_by_name(name)
        if not player then return false end
        local stack = player:get_wielded_item()
        if stack:get_name() == "" then return false, "Take the object in your hand." end
        local meta = stack:get_meta()
        local txt = meta:get_string("item_bind")
        if txt == "" then return true, "There are no active binds on this item." end
        local data = minetest.deserialize(txt)
        if not data then return false, "Reading error" end
        minetest.chat_send_player(name, "=== Information About Bind ===")
        minetest.chat_send_player(name, "cmd: /" .. data.cmd .. " " .. (data.param or ""))
        minetest.chat_send_player(name, "created: " .. data.creator .. " | Reloading: " .. data.cooldown .. "sec.")
        return true
    end,
})

minetest.register_on_punchnode(function(pos, node, puncher, pointed_thing)
    if not puncher or not puncher:is_player() then return end
    
    local name = puncher:get_player_name()
    local itemstack = puncher:get_wielded_item()
    if itemstack:is_empty() then return end
    
    local meta = itemstack:get_meta()
    local txt = meta:get_string("item_bind")
    if not txt or txt == "" then return end
    
    local current_clock = os.clock()
    if _click_lockout[name] and (current_clock - _click_lockout[name] < 0.05) then
        return
    end
    _click_lockout[name] = current_clock
    
    local current = minetest.deserialize(txt)
    if current and current.cmd and current.cmd ~= "" then
        local final_param = current.param or ""
        
        if current.is_tick then
            local user_privs = minetest.get_player_privs(name)
            if not user_privs.binds then
                minetest.chat_send_player(name, "You do not have the required binds privilege to execute tick!")
                return
            end
            if pointed_thing and pointed_thing.type == "object" then
                local target_obj = pointed_thing.ref
                if target_obj and target_obj:is_player() then
                    final_param = target_obj:get_player_name()
                else
                    return
                end
            else
                return
            end
        end
        
        local time = minetest.get_gametime()
        local cooldown_key = name .. "_" .. current.uuid
        if time < (_bind_cooldowns[cooldown_key] or 0) then
            minetest.chat_send_player(name, "Reloading")
            return
        end
        
        local success = run_bind_command(name, current.creator, current.cmd, final_param, current.playertrue)
        if success then
            if current.cooldown and current.cooldown > 0 then
                _bind_cooldowns[cooldown_key] = time + current.cooldown
            end
            if current.once then
                meta:set_string("item_bind", "")
                puncher:set_wielded_item(itemstack)
                minetest.chat_send_player(name, "The bind was executed and deleted.")
            end
        end
    end
end)
