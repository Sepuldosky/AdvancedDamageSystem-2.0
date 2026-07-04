local function BuildArmorPanel(p)
    p:ClearControls()
    p:Help("Advanced Damage System - Armor")

    p:Help("System Toggles")
    p:CheckBox("Enable NPC armor system","ads_enabled_npc")
    p:CheckBox("Enable Player armor system","ads_enabled_ply")
    p:CheckBox("Engine hitgroup compensation (limb/head HP)","ads_engine_hitgroup_compensation")

    p:Help("Global Armor Defaults (fallback when no override)")
    p:NumSlider("NPC Min Armor","ads_min_arm",0,100,0)
    p:NumSlider("NPC Max Armor","ads_max_arm",0,100,0)
    p:NumSlider("Player Spawn Armor","ads_ply_arm",0,100,0)
    p:NumSlider("Min Reduction %","ads_red_min",0,100,0)
    p:NumSlider("Max Reduction %","ads_red_max",0,100,0)

    p:Help("Zonal Armor Effectiveness")
    p:NumSlider("Helmet Effectiveness","ads_helmet_mult",0,1,2)
    p:NumSlider("Blast Effectiveness","ads_blast_mult",0,1,2)
    p:NumSlider("Crush Effectiveness","ads_crush_mult",0,1,2)

    p:Help("Global Damage Multipliers (override per classname via toolgun)")
    p:NumSlider("Head damage mult","ads_limb_mult_head",0,5,2)
    p:NumSlider("Chest damage mult","ads_limb_mult_chest",0,5,2)
    p:NumSlider("Arm damage mult","ads_limb_mult_arm",0,5,2)
    p:NumSlider("Leg damage mult","ads_limb_mult_leg",0,5,2)

    p:Help("Detection")
    p:CheckBox("Enable VJ auto-detect","ads_vj_autodetect")

    p:Help("Effects")
    p:CheckBox("Enable Armor Hit Sound","ads_sound_enabled")

    p:Help("Debug")
    p:CheckBox("Enable Debug Prints","ads_debug")

    p:Help("Reset")
    p:Button("Reset Armor Settings to Default").DoClick = function()
        Derma_Query("Reset Armor Settings to defaults?","ADS","Yes",function()
            RunConsoleCommand("ads_enabled_npc","1")
            RunConsoleCommand("ads_enabled_ply","1")
            RunConsoleCommand("ads_engine_hitgroup_compensation","1")
            RunConsoleCommand("ads_min_arm","0")
            RunConsoleCommand("ads_max_arm","100")
            RunConsoleCommand("ads_ply_arm","100")
            RunConsoleCommand("ads_red_min","15")
            RunConsoleCommand("ads_red_max","80")
            RunConsoleCommand("ads_helmet_mult","0.5")
            RunConsoleCommand("ads_blast_mult","0.5")
            RunConsoleCommand("ads_crush_mult","0.5")
            RunConsoleCommand("ads_limb_mult_head","1.0")
            RunConsoleCommand("ads_limb_mult_chest","1.0")
            RunConsoleCommand("ads_limb_mult_arm","1.0")
            RunConsoleCommand("ads_limb_mult_leg","1.0")
            RunConsoleCommand("ads_vj_autodetect","1")
            RunConsoleCommand("ads_sound_enabled","1")
            RunConsoleCommand("ads_debug","0")
        end,"No")
    end
end

local function BuildLimbsPanel(p)
    p:ClearControls()
    p:Help("Advanced Damage System - Limb HP")

    p:Help("System Toggle")
    p:CheckBox("Enable Limb HP System","ads_limbs_enabled")

    p:Help("HP Pool Fractions (per limb, fraction of NPC max HP)")
    p:NumSlider("Head HP fraction","ads_limb_head_frac",0,2,2)
    p:NumSlider("Arms HP fraction (per arm)","ads_limb_arms_frac",0,2,2)
    p:NumSlider("Legs HP fraction (per leg)","ads_limb_legs_frac",0,2,2)

    p:Help("Damage Transfer (fraction of damage that drains the pool)")
    p:NumSlider("Head damage transfer","ads_limb_damage_transfer_head",0,3,2)
    p:NumSlider("Arms damage transfer","ads_limb_damage_transfer_arms",0,3,2)
    p:NumSlider("Legs damage transfer","ads_limb_damage_transfer_legs",0,3,2)

    p:Help("Debuff Intensity")
    p:NumSlider("Max accuracy penalty per arm","ads_limb_accuracy_max_penalty_per_arm",0,5,2)
    p:NumSlider("Max accuracy penalty from head","ads_limb_accuracy_max_penalty_head",0,5,2)
    p:NumSlider("Min speed mult per leg","ads_limb_min_speed_mult_per_leg",0,1,2)

    p:Help("Head Stun Durations")
    p:NumSlider("Head stun 50% duration (s)","ads_limb_head_stun_50_duration",0,5,1)
    p:NumSlider("Head stun 25% duration (s)","ads_limb_head_stun_25_duration",0,10,1)

    p:Help("Reset")
    p:Button("Reset Limb HP Settings to Default").DoClick = function()
        Derma_Query("Reset Limb HP Settings to defaults?","ADS","Yes",function()
            RunConsoleCommand("ads_limbs_enabled","1")
            RunConsoleCommand("ads_limb_head_frac","0.5")
            RunConsoleCommand("ads_limb_arms_frac","0.5")
            RunConsoleCommand("ads_limb_legs_frac","0.5")
            RunConsoleCommand("ads_limb_damage_transfer_head","1.5")
            RunConsoleCommand("ads_limb_damage_transfer_arms","0.7")
            RunConsoleCommand("ads_limb_damage_transfer_legs","0.7")
            RunConsoleCommand("ads_limb_accuracy_max_penalty_per_arm","1.0")
            RunConsoleCommand("ads_limb_accuracy_max_penalty_head","0.5")
            RunConsoleCommand("ads_limb_min_speed_mult_per_leg","0.5")
            RunConsoleCommand("ads_limb_head_stun_50_duration","1.0")
            RunConsoleCommand("ads_limb_head_stun_25_duration","2.5")
        end,"No")
    end
end

local function BuildScavengerPanel(p)
    p:ClearControls()
    p:Help("Advanced Damage System - Scavenger")

    p:Help("System Toggle")
    p:CheckBox("Enable Scavenger","ads_scavenger_enabled")

    p:Help("Drop Lifetime and Cooldowns")
    p:NumSlider("Drop lifetime (seconds)","ads_scavenger_drop_lifetime",0,600,0)
    p:NumSlider("Post-drop cooldown (seconds)","ads_scavenger_post_drop_cooldown",0,60,0)
    p:NumSlider("Drop ownership time (seconds)","ads_scavenger_drop_ownership_time",0,300,0)

    p:Help("Detection")
    p:NumSlider("Search radius","ads_scavenger_search_radius",100,3000,0)
    p:NumSlider("Pickup distance","ads_scavenger_pickup_distance",10,200,0)
    p:NumSlider("Think interval (seconds)","ads_scavenger_think_interval",0.1,5,1)

    p:Help("Behavior Toggles")
    p:CheckBox("Allow combat interrupt for better weapons","ads_scavenger_interrupt_combat")
    p:CheckBox("Allow world weapons (map-spawned)","ads_scavenger_allow_world_weapons")
    p:CheckBox("Force all NPCs to scavenge (ignore detection)","ads_scavenger_force_all_npcs")

    p:Help("Movement Mode")
    local modeCombo = vgui.Create("DComboBox", p)
    modeCombo:SetTall(22)
    local currentMode = GetConVar("ads_scavenger_movement_mode") and GetConVar("ads_scavenger_movement_mode"):GetString() or "run"
    modeCombo:AddChoice("Run", "run", currentMode == "run")
    modeCombo:AddChoice("Walk", "walk", currentMode == "walk")
    modeCombo.OnSelect = function(_, _, _, data)
        RunConsoleCommand("ads_scavenger_movement_mode", data)
    end
    p:AddItem(modeCombo)

    p:Help("Debug")
    p:CheckBox("Scavenger debug prints","ads_scavenger_debug")

    p:Help("Reset")
    p:Button("Reset Scavenger Settings to Default").DoClick = function()
        Derma_Query("Reset Scavenger Settings to defaults?","ADS","Yes",function()
            RunConsoleCommand("ads_scavenger_enabled","1")
            RunConsoleCommand("ads_scavenger_drop_lifetime","60")
            RunConsoleCommand("ads_scavenger_post_drop_cooldown","8")
            RunConsoleCommand("ads_scavenger_drop_ownership_time","30")
            RunConsoleCommand("ads_scavenger_search_radius","800")
            RunConsoleCommand("ads_scavenger_pickup_distance","40")
            RunConsoleCommand("ads_scavenger_think_interval","0.5")
            RunConsoleCommand("ads_scavenger_interrupt_combat","0")
            RunConsoleCommand("ads_scavenger_allow_world_weapons","0")
            RunConsoleCommand("ads_scavenger_force_all_npcs","0")
            RunConsoleCommand("ads_scavenger_movement_mode","run")
            RunConsoleCommand("ads_scavenger_debug","0")
        end,"No")
    end
end

local function BuildHelpPanel(p)
    p:ClearControls()
    p:Help("Advanced Damage System - Usage Guide")

    p:Help("Overview")
    p:Help("ADS adds a zonal armor and damage-scaling system for NPCs and players. It blocks certain damage types on specific body zones and lets you tune damage per hitgroup globally or per-NPC.")

    p:Help("Detection Layers (priority order)")
    p:Help("1. User blacklist - NPC does NOT carry armor")
    p:Help("2. User whitelist - NPC DOES carry armor (with optional per-class values)")
    p:Help("3. Hardcoded blacklist - known civilians that share classes with soldiers")
    p:Help("4. Hardcoded whitelist - HL2 vanilla combine/metropolice/citizen/alyx/barney")
    p:Help("5. VJ classname patterns (vj_hsold, vj_combine, vj_cswat, etc.)")
    p:Help("6. VJ auto-detect via VJ_NPC_Class (CLASS_COMBINE, CLASS_UNITED_STATES, etc.)")

    p:Help("Armor mechanics")
    p:Help("Armor absorbs damage only on protected zones: torso, generic and stomach hitgroups always protected, head uses the helmet multiplier, other zones pass through unless Full Body is enabled.")
    p:Help("Blockable damage types: bullet, buckshot, club, slash, blast, sniper (incl. ARC9 custom), crush.")
    p:Help("Blast and crush ignore hitgroup and use their dedicated effectiveness multipliers.")
    p:Help("Armor wears down 15% of whatever it blocked.")

    p:Help("Damage Multipliers (second pass)")
    p:Help("After armor is applied, a damage multiplier is applied per hitgroup. Uses per-classname override first, otherwise falls back to the global multiplier sliders in Armor Settings. Value 1.0 means no change. Only affects NPCs, never players. Explosions and crush are not affected by this pass.")

    p:Help("Toolgun workflow")
    p:Help("Left click on NPC: whitelist that classname using the current tool sliders (armor, reduction, full body, damage multipliers). If the NPC was blacklisted, it moves to whitelist automatically.")
    p:Help("Right click on NPC: toggle blacklist. If whitelisted, moves to blacklist.")
    p:Help("Reload (R) on NPC: print inspection details to client console and show notification.")

    p:Help("Tool sliders at 1.0 for all damage multipliers = no dmg_mult saved in JSON (uses globals).")

    p:Help("Config persistence")
    p:Help("User whitelist and blacklist are saved to data/ads/ads_config.json on the server after every change.")

    p:Help("Debug")
    p:Help("Enable Debug Prints in Armor Settings to see spawn, armor hits, zone rejections and multiplier applications in server console.")
    p:Help("Enable Scavenger debug prints in Scavenger Settings to see weapon search, pickup and equip events.")
end

hook.Add("PopulateToolMenu","ADS_RegisterMenu",function()
    spawnmenu.AddToolMenuOption("Options","Advanced Damage System","ADS_Armor",     "Armor Settings",     "","",BuildArmorPanel)
    spawnmenu.AddToolMenuOption("Options","Advanced Damage System","ADS_Limbs",     "Limb HP Settings",   "","",BuildLimbsPanel)
    spawnmenu.AddToolMenuOption("Options","Advanced Damage System","ADS_Scavenger", "Scavenger Settings", "","",BuildScavengerPanel)
    spawnmenu.AddToolMenuOption("Options","Advanced Damage System","ADS_Help",      "How to use",         "","",BuildHelpPanel)
end)
