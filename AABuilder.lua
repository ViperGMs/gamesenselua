-- #region menu references
local references = {
    pitch = ui.reference("AA", "Anti-aimbot angles", "Pitch"),
    yaw = {ui.reference("AA", "Anti-aimbot angles", "Yaw")},
    yawjitter = {ui.reference("AA", "Anti-aimbot angles", "Yaw jitter")},
    bodyyaw = {ui.reference("AA", "Anti-aimbot angles", "Body yaw")},
    lbytarget = ui.reference("AA", "Anti-aimbot angles", "Lower body yaw target"),
    fakelimit = ui.reference("AA", "Anti-aimbot angles", "Fake yaw limit")
}
-- #endregion

-- #region data
local lasttime = 0
local current_stage = 1
local should_switch = false
local can_switch_hotkey = true
local brute_timer = 0
local brute_last_miss = 0
local stage_names = database.read("aabuilder_names") or {}
local stage_data = database.read("aabuilder_data") or {}
local stage_configs = database.read("aabuilder_configs") or {}
local menu_loc = {"LUA", "A", "B"}
-- #endregion

-- #region helper functions
local function table_includes(table, key)
    local contains = false
    for i = 1, #table do
        if table[i] == key then
            contains = true
        end
    end
    return contains
end

local function GetClosestPoint(A, B, P) -- this is stolen because math is hard
    local a_to_p = { P[1] - A[1], P[2] - A[2] }
    local a_to_b = { B[1] - A[1], B[2] - A[2] }

    local atb2 = a_to_b[1]^2 + a_to_b[2]^2

    local atp_dot_atb = a_to_p[1]*a_to_b[1] + a_to_p[2]*a_to_b[2]
    local t = atp_dot_atb / atb2
    
    return { A[1] + a_to_b[1]*t, A[2] + a_to_b[2]*t }
end
-- #endregion

-- #region ui elements
local use_antiaim_builder = ui.new_checkbox(menu_loc[1], menu_loc[2], "Use AA builder") 
local show_antiaim_builder = ui.new_checkbox(menu_loc[1], menu_loc[3], "Show AA builder ("..menu_loc[1].. ", ".. menu_loc[2].. ") ".. "("..menu_loc[1].. ", ".. menu_loc[3].. ")") 
local show_antiaim_indicator = ui.new_checkbox(menu_loc[1], menu_loc[2], "Show current stage as indicator") 
local print_stage_changes = ui.new_checkbox(menu_loc[1], menu_loc[3], "Print stage changes to console") 

local stage_list = ui.new_listbox(menu_loc[1], menu_loc[2], "Current stages", stage_names)
local stage_text = ui.new_textbox(menu_loc[1], menu_loc[2], "Stage text")
local add_stage = ui.new_button(menu_loc[1], menu_loc[2], "Add stage", function()
    if ui.get(stage_text) ~= "" then 
        stage_names[#stage_names+1] = ui.get(stage_text)
        stage_data[#stage_data+1] = {
            timer = 16,
            pitch = "Down",
            yaw = "180",
            yawval = 0,
            jitter = "Off",
            jitterval = 0,
            bodyyaw = "Static",
            bodyyawval = 60,
            lbytarget = "Eye yaw",
            fakelimit = 60
        }
        ui.update(stage_list, stage_names)
        ui.set(stage_text, "")

        if #stage_names == 1 then -- ghetto way to update for bruteforce
            should_switch = true
        end
    end
end)
local rename_stage = ui.new_button(menu_loc[1], menu_loc[2], "Update stage name", function()
    if ui.get(stage_text) ~= "" then
        stage_names[ui.get(stage_list)+1] = ui.get(stage_text)
        ui.update(stage_list, stage_names)
    end
end)

local remove_stage = ui.new_button(menu_loc[1], menu_loc[2], "Remove stage", function()
    if #stage_names > 0 then
        table.remove(stage_names, ui.get(stage_list)+1)
        table.remove(stage_data, ui.get(stage_list)+1)
        ui.update(stage_list, stage_names)
        ui.set(stage_text, "")
    end
end)

local antiaim_switch_type = ui.new_combobox(menu_loc[1], menu_loc[2], "Antiaim switch type", {"Timer", "Bruteforce", "Hotkey"})

local config_selector = ui.new_listbox(menu_loc[1], menu_loc[3], "Config selector", stage_configs)
local config_text = ui.new_textbox(menu_loc[1], menu_loc[3], "Config text")
local save_config = ui.new_button(menu_loc[1], menu_loc[3], "Save config", function()
    local temp_table = {}

    if ui.get(config_text) ~= "" then
        if not table_includes(stage_configs, ui.get(config_text)) then
            stage_configs[#stage_configs+1] = ui.get(config_text)
            ui.update(config_selector, stage_configs)
        end

        for i = 1, #stage_data do -- store all data into a table
            temp_table[#temp_table+1] = {
                id = stage_names[i], 
                data = {
                    timer = stage_data[i].timer,
                    pitch = stage_data[i].pitch,
                    yaw = stage_data[i].yaw,
                    yawval = stage_data[i].yawval,
                    jitter = stage_data[i].jitter,
                    jitterval = stage_data[i].jitterval,
                    bodyyaw = stage_data[i].bodyyaw,
                    bodyyawval = stage_data[i].bodyyawval,
                    lbytarget = stage_data[i].lbytarget,
                    fakelimit = stage_data[i].fakelimit
                }
            }
        end
        temp_table[#temp_table+1] = ui.get(antiaim_switch_type)

        database.write("aabuilder_data_"..ui.get(config_text), temp_table) -- write the table to the database
    end
end)

local load_config = ui.new_button(menu_loc[1], menu_loc[3], "Load config", function()
    if #stage_configs > 0 then
        stage_names = {}
        stage_data = {}

        local temp_table = database.read("aabuilder_data_"..ui.get(config_text))
        for i = 1, #temp_table-1 do
            stage_names[#stage_names+1] = temp_table[i].id
            stage_data[#stage_data+1] = temp_table[i].data
        end
        ui.set(antiaim_switch_type, temp_table[#temp_table])

        ui.update(stage_list, stage_names)
    end
end)

local delete_config = ui.new_button(menu_loc[1], menu_loc[3], "Delete config", function()
    if #stage_configs > 0 then
        database.write("aabuilder_data_"..ui.get(config_text), nil)
        table.remove(stage_configs, ui.get(config_selector)+1)
        ui.set(config_text, "")
        ui.update(config_selector, stage_configs)
    end
end)

local next_stage = ui.new_hotkey(menu_loc[1], menu_loc[2], "Next stage", false)
local stage_timer = ui.new_slider(menu_loc[1], menu_loc[2], "Time to next stage", 16, 1100, 500, true, "ms")
local stage_pitch = ui.new_combobox(menu_loc[1], menu_loc[2], "Pitch", {"Off", "Up", "Down"})
local stage_yaw = ui.new_combobox(menu_loc[1], menu_loc[2], "Yaw", {"Off", "180", "Spin", "Static", "180 Z", "Crosshair"})
local stage_yawval = ui.new_slider(menu_loc[1], menu_loc[2], "\nYaw", -180, 180, 0)
local stage_jitter = ui.new_combobox(menu_loc[1], menu_loc[3], "Yaw jitter", {"Off", "Offset", "Center", "Random"})
local stage_jitterval = ui.new_slider(menu_loc[1], menu_loc[3], "\nYaw jitter", -180, 180, 0)
local stage_bodyyaw = ui.new_combobox(menu_loc[1], menu_loc[3], "Body yaw", {"Off", "Static", "Jitter", "Opposite"})
local stage_bodyyawval = ui.new_slider(menu_loc[1], menu_loc[3], "\nBody yaw", -180, 180, 58)
local stage_lbytarget = ui.new_combobox(menu_loc[1], menu_loc[3], "Lower body yaw target", {"Off", "Eye yaw", "Opposite", "Sway"})
local stage_fakelimit = ui.new_slider(menu_loc[1], menu_loc[3], "Fake yaw limit", 0, 60, 58)
-- #endregion

-- #region ui callbacks
-- use_antiaim_builder is at the bottom of the script
local function handle_visibility()
    local bool = ui.get(show_antiaim_builder) and ui.get(use_antiaim_builder)

    ui.set_visible(stage_list, bool)
    ui.set_visible(stage_text, bool)
    ui.set_visible(add_stage, bool)
    ui.set_visible(rename_stage, bool)
    ui.set_visible(remove_stage, bool)

    ui.set_visible(show_antiaim_indicator, bool)
    ui.set_visible(print_stage_changes, bool)

    ui.set_visible(antiaim_switch_type, bool)
    ui.set_visible(next_stage, bool and ui.get(antiaim_switch_type) == "Hotkey")

    ui.set_visible(stage_timer, bool and ui.get(antiaim_switch_type) == "Timer")
    ui.set_visible(stage_pitch, bool)
    ui.set_visible(stage_yaw, bool)
    ui.set_visible(stage_yawval, bool and ui.get(stage_yaw) ~= "Off")
    ui.set_visible(stage_jitter, bool)
    ui.set_visible(stage_jitterval, bool and ui.get(stage_jitter) ~= "Off")
    ui.set_visible(stage_bodyyaw, bool)
    ui.set_visible(stage_bodyyawval, bool and ui.get(stage_bodyyaw) ~= "Off" and ui.get(stage_bodyyaw) ~= "Opposite")
    ui.set_visible(stage_lbytarget, bool)
    ui.set_visible(stage_fakelimit, bool and ui.get(stage_bodyyaw) ~= "Off")

    ui.set_visible(config_selector, bool)
    ui.set_visible(config_text, bool)
    ui.set_visible(save_config, bool)
    ui.set_visible(load_config, bool)
    ui.set_visible(delete_config, bool)
end

ui.set_callback(show_antiaim_builder, handle_visibility)
ui.set_callback(antiaim_switch_type, handle_visibility)
handle_visibility()

local function handle_visibility2()
    ui.set_visible(show_antiaim_builder, ui.get(use_antiaim_builder))
end

ui.set_callback(stage_list, function()
    local cur_data = stage_data[ui.get(stage_list)+1]

    handle_visibility()

    ui.set(stage_timer, cur_data.timer)
    ui.set(stage_pitch, cur_data.pitch)
    ui.set(stage_yaw, cur_data.yaw)
    ui.set(stage_yawval, cur_data.yawval)
    ui.set(stage_jitter, cur_data.jitter)
    ui.set(stage_jitterval, cur_data.jitterval)
    ui.set(stage_bodyyaw, cur_data.bodyyaw)
    ui.set(stage_bodyyawval, cur_data.bodyyawval)
    ui.set(stage_lbytarget, cur_data.lbytarget)
    ui.set(stage_fakelimit, cur_data.fakelimit)
end)

ui.set_callback(config_selector, function()
    ui.set(config_text, stage_configs[ui.get(config_selector)+1])
end)

-- done individually because stupid error made it not work when I did them together
-- would only set the top one
-- might try to fix later, idk
ui.set_callback(stage_timer, function()
    if #stage_data > 0 then
        client.delay_call(0.0001, function()
            stage_data[ui.get(stage_list)+1].timer = ui.get(stage_timer)
        end)
    end
end)

ui.set_callback(stage_pitch, function()
    if #stage_data > 0 then
        client.delay_call(0.0001, function()
            stage_data[ui.get(stage_list)+1].pitch = ui.get(stage_pitch)
        end)
    end
end)

ui.set_callback(stage_yaw, function()
    if #stage_data > 0 then
        client.delay_call(0.0001, function()
            stage_data[ui.get(stage_list)+1].yaw = ui.get(stage_yaw)
        end)
    end
    handle_visibility()
end)

ui.set_callback(stage_yawval, function()
    if #stage_data > 0 then
        client.delay_call(0.0001, function()
            stage_data[ui.get(stage_list)+1].yawval = ui.get(stage_yawval)
        end)
    end
end)

ui.set_callback(stage_jitter, function()
    if #stage_data > 0 then
        client.delay_call(0.0001, function()
            stage_data[ui.get(stage_list)+1].jitter = ui.get(stage_jitter)
        end)
    end
    handle_visibility()
end)

ui.set_callback(stage_jitterval, function()
    if #stage_data > 0 then
        client.delay_call(0.0001, function()
            stage_data[ui.get(stage_list)+1].jitterval = ui.get(stage_jitterval)
        end)
    end
end)

ui.set_callback(stage_bodyyaw, function()
    if #stage_data > 0 then
        client.delay_call(0.0001, function()
            stage_data[ui.get(stage_list)+1].bodyyaw = ui.get(stage_bodyyaw)
        end)
    end
    handle_visibility()
end)

ui.set_callback(stage_bodyyawval, function()
    if #stage_data > 0 then
        client.delay_call(0.0001, function()
            stage_data[ui.get(stage_list)+1].bodyyawval = ui.get(stage_bodyyawval)
        end)
    end
end)

ui.set_callback(stage_lbytarget, function()
    if #stage_data > 0 then
        client.delay_call(0.0001, function()
            stage_data[ui.get(stage_list)+1].lbytarget = ui.get(stage_lbytarget)
        end)
    end
end)

ui.set_callback(stage_fakelimit, function()
    if #stage_data > 0 then
        client.delay_call(0.0001, function()
            stage_data[ui.get(stage_list)+1].fakelimit = ui.get(stage_fakelimit)
        end)
    end
end)
-- #endregion

-- #region event callbacks
local function on_bullet_impact(e) -- stolen from some bruteforce lua, im way too lazy to do this myself
    if ui.get(antiaim_switch_type) ~= "Bruteforce" then
        return
    end

    local ent = client.userid_to_entindex(e.userid)
    if not entity.is_dormant(ent) and entity.is_enemy(ent) then
        local ent_shoot = { entity.get_prop(ent, "m_vecOrigin") }
        ent_shoot[3] = ent_shoot[3] + entity.get_prop(ent, "m_vecViewOffset[2]")
        local player_head = { entity.hitbox_position(entity.get_local_player(), 0) }
        local closest = GetClosestPoint(ent_shoot, { e.x, e.y, e.z }, player_head)
        local delta = { player_head[1]-closest[1], player_head[2]-closest[2] }
        local delta_2d = math.sqrt(delta[1]^2+delta[2]^2)
        
        if math.abs(delta_2d) <= 35 and globals.realtime() - brute_last_miss > 0.2 then
            should_switch = true
            brute_timer = globals.realtime() + 5
            brute_last_miss = globals.realtime()
        end
    end
end

local function on_setup_command()
    if #stage_names ~= 0 and #stage_data ~= 0 then

        if ui.get(antiaim_switch_type) == "Timer" then
            if globals.realtime() > lasttime then
                lasttime = globals.realtime() + (stage_data[current_stage].timer/1000)
                should_switch = true
            end
        elseif ui.get(antiaim_switch_type) == "Hotkey" then
            if ui.get(next_stage) and can_switch_hotkey then
                should_switch = true
                can_switch_hotkey = false
            end

            if not ui.get(next_stage) and not can_switch_hotkey then
                can_switch_hotkey = true
            end
        elseif ui.get(antiaim_switch_type) == "Bruteforce" then
            if brute_timer < globals.realtime() then
                current_stage = 0
                should_switch = true
                brute_timer = globals.realtime() + 99999 -- prevent it from reseting multiple times
            end

            if ui.is_menu_open() and not can_switch_hotkey then
                can_switch_hotkey = true
            end

            if not ui.is_menu_open() and can_switch_hotkey then
                current_stage = 0
                should_switch = true
                can_switch_hotkey = false
            end
        end

        if ui.is_menu_open() then
            current_stage = ui.get(stage_list)
            should_switch = true
        end

        if should_switch then
            current_stage = current_stage + 1

            if current_stage > #stage_names then 
                current_stage = 1 
            end

            local cur_data = stage_data[current_stage]

            ui.set(references.pitch, cur_data.pitch)
            ui.set(references.yaw[1], cur_data.yaw)
            ui.set(references.yaw[2], cur_data.yawval)
            ui.set(references.yawjitter[1], cur_data.jitter)
            ui.set(references.yawjitter[2], cur_data.jitterval)
            ui.set(references.bodyyaw[1], cur_data.bodyyaw)
            ui.set(references.bodyyaw[2], cur_data.bodyyawval)
            ui.set(references.lbytarget, cur_data.lbytarget)
            ui.set(references.fakelimit, cur_data.fakelimit)

            if ui.get(print_stage_changes) and not ui.is_menu_open() then
                print("Stage changed to ", stage_names[current_stage])
            end

            should_switch = false
        end
    end
end

local function on_paint()
    if stage_names[current_stage] ~= nil and ui.get(show_antiaim_indicator) then
        renderer.indicator(255, 255, 255, 200, "[S] ", stage_names[current_stage])
    end
end

local function on_prestart()
    if ui.get(antiaim_switch_type) == "Bruteforce" then -- reset bruteforce on round start
        current_stage = 1
    end
end

client.set_event_callback("player_connect_full", function() -- prevents lua from not working on new map (curtime would be way under lasttime)
    lasttime = 0
    current_stage = 1
end)

client.set_event_callback("shutdown", function()
    database.write("aabuilder_names", stage_names)
    database.write("aabuilder_data", stage_data)
    database.write("aabuilder_configs", stage_configs)
end)

ui.set_callback(use_antiaim_builder, function()
    handle_visibility()
    handle_visibility2()

    if ui.get(use_antiaim_builder) then
        client.set_event_callback("bullet_impact", on_bullet_impact)
        client.set_event_callback("setup_command", on_setup_command)
        client.set_event_callback("paint", on_paint)
        client.set_event_callback("round_prestart", on_prestart)
    else
        client.unset_event_callback("bullet_impact", on_bullet_impact)
        client.unset_event_callback("setup_command", on_setup_command)
        client.unset_event_callback("paint", on_paint)
        client.unset_event_callback("round_prestart", on_prestart)
    end
end)
handle_visibility2()
-- #endregion

-- #region initialize
ui.set(show_antiaim_builder, true)
-- #endregion