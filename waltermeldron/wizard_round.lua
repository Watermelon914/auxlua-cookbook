SS13 = require("SS13")

local GLOB = dm.global_vars:get_var("GLOB")
local SSdcs = dm.global_vars:get_var("SSdcs")
local SSid_access = dm.global_vars:get_var("SSid_access")
local SSmapping = dm.global_vars:get_var("SSmapping")
local rules = "You are a wizard! You can do whatever you want on the station!\nNote: Antimagic is completely disabled\nRespawns are enabled\nPick up IDs to gain score!"

local allHuds = {}
local leaderboard = {}
local players = {}
local idCards = {}

local BANNED_SPELLS = {
    "/datum/spellbook_entry/summon",
    "/datum/spellbook_entry/lichdom",
    "/datum/spellbook_entry/summon_simians",
    "/datum/spellbook_entry/bees"
}

local function REF(atom)
    return dm.global_proc("REF", atom)
end

local function updateLeaderboard(image)
    table.sort(leaderboard, function(a, b)
        return a.idsPickedUp > b.idsPickedUp
    end)
    local leaderboard_text = ""
    for i = 1, 5 do
        local playerData = leaderboard[i]
        if playerData then 
            leaderboard_text = leaderboard_text .. "<br/>[" .. playerData.idsPickedUp .. "] " .. playerData.name
        end
    end
    local text = string.format("<span class='maptext' style='color: %s'>Most IDs collected%s</span>", "#ffffff", leaderboard_text)
    if image then
        image:set_var(
            "maptext",
            text
        )
    else
        for currentImage, _ in allHuds do
            if SS13.is_valid(currentImage) then
                currentImage:set_var(
                    "maptext",
                    text
                )
            else
                allHuds[currentImage] = nil
            end
        end
    end
end

-- Magical
local function makeWizard(oldmob, job)
    local mind = oldmob.vars.mind
	if mind ~= nil then
        if job == nil or job:is_null() then
            job = mind.vars.assigned_role
            if job == nil or job:is_null() or job.vars.outfit == nil then
                job = dm.global_vars:get_var("SSjob"):get_var("name_occupations"):get("Assistant")
            end
        end
        SS13.register_signal(mind, "antagonist_gained", function(_, wizard_antag)
            local mob = mind:get_var("current")
            wizard_antag:set_var("allow_rename", false)
            dm.global_proc("qdel", wizard_antag:get_var("ritual"))
            local ckey = mob:get_var("ckey")
            mob:set_var("real_name", mob:get_var("key"))
            local outfit = job.vars.outfit
            local id
            if outfit ~= nil then
                outfit = dm.global_proc("_new", outfit)
                id = SS13.new(outfit.vars.id)
                id:set_var("registered_name", ckey)
                SSid_access:call_proc("apply_trim_to_card", id, outfit.vars.id_trim)
                local ref = REF(id)
                idCards[ref] = mind
                SS13.register_signal(id, "parent_qdeleting", function(_)
                    idCards[ref] = nil
                end)
            end
            local image = SS13.new("/atom/movable/screen/text")
            local readyUpButton = SS13.new("/atom/movable/screen/text")
            image:set_var("screen_loc", "WEST:4,CENTER-0:17")
            readyUpButton:set_var("screen_loc", "WEST:4,CENTER-0:0")
            readyUpButton:set_var("maptext", "<span class='maptext' style='color: #ffa8a8'>Join the battle</span>")
            readyUpButton:set_var("maptext_width", 120)
            readyUpButton:set_var("maptext_height", 15)
            readyUpButton:set_var("mouse_opacity", 2)
            local hud = mob:get_var("hud_used")
            local hudElements = hud:get_var("static_inventory")
            hudElements:add(image)
            hudElements:add(readyUpButton)
            allHuds[image] = true
            hud:call_proc("show_hud", hud:get_var("hud_version"))
            if not players[ckey] then
                players[ckey] = {
                    name = ckey,
                    idsPickedUp = 0,
                    idCard = id
                }
                table.insert(leaderboard, players[ckey])
            end
            updateLeaderboard(image)
            local playerData = players[ckey]
            dm.global_proc("to_chat", mob, "<span class='big bold hypnophrase'>" .. rules .. "</span>")
            dm.global_proc("_add_trait", mob, "pacifism", "admin_voodoo")
            SS13.register_signal(readyUpButton, "screen_element_click", function(_, _, _ , _, clickingUser)
                if clickingUser ~= mind:get_var("current") then
                    return
                end
                mob:call_proc("forceMove", dm.global_proc("get_safe_random_station_turf"))
                hudElements:remove(readyUpButton)
                SS13.qdel(readyUpButton)
                hud:call_proc("show_hud", hud:get_var("hud_version"))
            end)
            function register_mob_signals(old, mob_target)
                if old ~= nil and not old:is_null() then
                    SS13.unregister_signal(old, "addtrait anti_magic")
                    SS13.unregister_signal(old, "mob_equipped_item")
                    SS13.unregister_signal(old, "addtrait anti_magic_no_selfblock")
                    SS13.unregister_signal(old, "mob_statchange")
                    SS13.unregister_signal(old, "mob_logout")
                    SS13.unregister_signal(old, "try_invoke_spell")
                    SS13.unregister_signal(old, "movable_moved")
                end
                SS13.register_signal(mob_target, "try_invoke_spell", function()
                    local playerLoc = dm.global_proc("_get_step", mob_target, 0)
                    local playerArea = playerLoc:get_var("loc")
                    if bit32.band(playerArea:get_var("area_flags"), 320) == 320 then
                        return 1
                    end
                end)
                SS13.register_signal(mob_target, "addtrait anti_magic", function(_, trait)
                    local traits = mob_target:get_var("_status_traits")
                    traits:remove(trait)
                end)
                SS13.register_signal(mob_target, "addtrait anti_magic_no_selfblock", function(_, trait)
                    local traits = mob_target:get_var("_status_traits")
                    traits:remove(trait)
                end)
                SS13.register_signal(mob_target, "mob_equipped_item", function(_, item)
                    dm.global_proc("qdel", item:call_proc("GetComponent", dm.global_proc("_text2path", "/datum/component/anti_magic")))
                end)
                SS13.register_signal(mob_target, "mob_clickon", function(_, item, modifiers)
                    if mob_target:call_proc("incapacitated") == 1 then
                        return
                    end

                    if item:get_var("loc") ~= mob_target then
                        if dm.global_proc("_get_dist", mob_target, item) > 1 then
                            return
                        end
                    end
                    local itemRef = REF(item)
                    local playerMind = idCards[itemRef]
                    if playerMind and playerMind ~= mind and item:get_var("registered_name") ~= mob_target:get_var("ckey") then
                        playerData.idsPickedUp += 1
                        dm.global_proc("qdel", item)
                        updateLeaderboard()
                    end
                end)
                SS13.register_signal(mob_target, "movable_moved", function(_, _)
                    local playerLoc = dm.global_proc("_get_step", mob_target, 0)
                    local playerArea = playerLoc:get_var("loc")
                    if bit32.band(playerArea:get_var("area_flags"), 320) ~= 320 then
                        dm.global_proc("_remove_trait", mob_target, "pacifism", "admin_voodoo")
                    end
                end)
                SS13.register_signal(mob_target, "mob_statchange", function(_, new_stat)
                    if new_stat == 4 and SS13.is_valid(id) then
                        local playerLoc = dm.global_proc("_get_step", mob_target, 0)
                        local playerArea = playerLoc:get_var("loc")
                        if bit32.band(playerArea:get_var("area_flags"), 320) ~= 320 then
                            id:call_proc("forceMove", playerLoc)
                        end
                    end
                end)
                SS13.register_signal(mob_target, "mob_logout", function(_)
                    if SSmapping:call_proc("level_trait", mob_target:get_var("z"), "Transit/Reserved") == 1 and SS13.is_valid(mob_target) then
                        SS13.set_timeout(0, function()
                            mob_target:set_var("ckey", nil)
                            mob_target:call_proc("dust")
                        end)
                    end
                end)
            end
            SS13.register_signal(mind, "mind_transferred", function(_, old)
                local current = mind:get_var("current")
                register_mob_signals(old, current)
            end)
            for _, telescroll in mob:get_var("contents"):of_type("/obj/item/teleportation_scroll") do
                dm.global_proc("qdel", telescroll)
            end
            for _, spellbook in mob:get_var("back"):get_var("contents"):of_type("/obj/item/spellbook") do
                for _, spell in spellbook:get_var("entries") do
                    for _, banned in BANNED_SPELLS do
                        if SS13.istype(spell, banned) then
                            spell:set_var("limit", 0)
                            spell:set_var("cost", 100)
                        end
                    end
                end
            end
            register_mob_signals(mob, mob)
            SS13.unregister_signal(mind, "antagonist_gained")
        end)
        SS13.await(mind, "make_wizard")
	end
end

-- Initial wizard creation
for _, mob in GLOB.vars.alive_player_list:to_table() do
    if over_exec_usage(0.7) then
        sleep()
    end
    makeWizard(mob)
end

local function latejoinSpawnCallback(_source, job, mob)
    makeWizard(mob, job)
end

function setupDeadPlayer(newMob)
    local image = SS13.new("/atom/movable/screen/text")
    local respawnButton = SS13.new("/atom/movable/screen/text")
    image:set_var("screen_loc", "WEST:4,CENTER-0:17")
    local hud = newMob:get_var("hud_used")
    local hudElements = hud:get_var("static_inventory")
    respawnButton:set_var("screen_loc", "WEST:4,CENTER-0:0")
    respawnButton:set_var("maptext", "<span class='maptext' style='color: #ffa8a8'>Respawn</span>")
    respawnButton:set_var("maptext_width", 120)
    respawnButton:set_var("maptext_height", 15)
    respawnButton:set_var("mouse_opacity", 2)
    hudElements:add(image)
    hudElements:add(respawnButton)
    allHuds[image] = true
    hud:call_proc("show_hud", hud:get_var("hud_version"))
    updateLeaderboard(image)
    SS13.register_signal(respawnButton, "screen_element_click", function(_, _, _ , _, clickingUser)
        if clickingUser ~= newMob then
            return
        end
        local newHuman
        SS13.set_timeout(0, function()
            newHuman = SS13.new("/mob/living/carbon/human", dm.global_proc("_pick_list", GLOB:get_var("wizardstart")))
            newHuman:set_var("key", newMob:get_var("key"))
        end)
        SS13.set_timeout(0.1, function()
            makeWizard(newHuman)
        end)
    end)
end

SS13.register_signal(SSdcs, "!job_after_latejoin_spawn", latejoinSpawnCallback)
SS13.register_signal(SSdcs, "!atom_after_post_init", function(_, newMob)
    if SS13.istype(newMob, "/mob/dead") then
        SS13.set_timeout(1, function()
            setupDeadPlayer(newMob)
        end)
    end
end)

for _, player in GLOB:get_var("current_observers_list") do
    if over_exec_usage(0.7) then
        sleep()
    end
    setupDeadPlayer(player)
end

for _, machine in dm.global_vars:get_var("SSmachines"):get_var("machines_by_type"):get(SS13.type("/obj/machinery/porta_turret/ai")) do
    SS13.qdel(machine)
end