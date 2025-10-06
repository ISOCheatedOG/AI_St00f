// =====================================================================
//  mod_menu_pro.gsc
//  "Pro" — Advanced Mod Menu Base for CoD5 / World at War
//  - Per-player menus
//  - Infinite wrap-around scrolling
//  - Submenus & nested categories
//  - Toggles (godmode, noclip, etc.)
//  - Teleports, give weapons, fun mods
//  - Animated HUD background, glow, and color cycling
//  - Player List submenu (select a player -> actions)
//  - Stat Editor submenu (XP, kills, prestige presets & increments)
//  - Save / Load config per-player (stored in level.menuConfigs by entnum)
//  - Sound effects (placeholders)
//  - All behavior uses standard GSC-style functions (replace engine-specific functions if needed)
// =====================================================================
//
//  Integration:
//   * Put this file in your mod's GSC folder and call `level thread init_mod_menu();`
//   * Hook input notifications per-player (see bottom for example notification calls)
//   * Replace placeholder functions like giveWeapon(), playSound() with your engine's equivalents if needed
//
//  Notes:
//   * This script uses per-player HudElems and threads; adjust resource usage for large servers
//   * Save/Load stores config in `level.menuConfigs[entnum]`. This persists while the map is loaded.
// =====================================================================

init_mod_menu()
{
    if (!isdefined(level.menuConfigs)) level.menuConfigs = [];
    level thread onPlayerConnect();
    level thread global_menu_admin_listener(); // optional server-wide admin commands
}

// When players connect, create their menu threads
onPlayerConnect()
{
    for (;;)
    {
        level waittill("connected", player);
        if (isdefined(player))
            player thread menu_init();
    }
}

// ===================================================================
// Per-player menu init
// ===================================================================
menu_init()
{
    self endon("disconnect");
    // Basic menu state
    self.menuOpen = false;
    self.menuLayer = 0;        // 0 = main, 1 = submenu, 2 = sub-sub (like player actions)
    self.menuIndex = 0;
    self.visibleWindowSize = 7;
    self.currentMenu = [];
    self.menuHistory = [];
    self.playerListIndex = 0;  // for Player List submenu index
    self.targetPlayer = undefined; // selected target player in player list

    // Persistent config storage slot
    self.configSlot = self.entnum; // use entity number to key level.menuConfigs

    // Default toggles/state
    self.godMode = false;
    self.unlimitedAmmo = false;
    self.noclip = false;
    self.ufo = false;
    self.superSpeed = false;
    self.infinitePoints = false;
    self.rainbowHud = false;
    self.hudGlow = true;

    // Saved teleport location
    self.savedPos = undefined;

    // Build menus
    self.mainMenu = [
        "Host Menu",
        "Weapons Menu",
        "Fun Menu",
        "Player Mods",
        "Stat Editor",
        "Visual Mods",
        "Teleport Menu",
        "Save Config",
        "Load Config",
        "Close Menu"
    ];

    self.subMenus = [];
    self.subMenus["Host Menu"] = [
        "God Mode",
        "Unlimited Ammo",
        "UFO Mode",
        "Noclip",
        "Super Speed",
        "Infinite Points",
        "Back"
    ];

    self.subMenus["Weapons Menu"] = [
        "Give Ray Gun",
        "Give PPSH",
        "Give All Weapons",
        "Clear Weapons",
        "Back"
    ];

    self.subMenus["Fun Menu"] = [
        "Third Person",
        "Explosive Bullets",
        "Gravity Gun",
        "Rainbow HUD",
        "Back"
    ];

    // Player Mods has dynamic listing (player list)
    self.subMenus["Player Mods"] = [
        "Open Player List",
        "Back"
    ];

    self.subMenus["Stat Editor"] = [
        "Set XP: +1000",
        "Set XP: +10000",
        "Set XP: MAX",
        "Add Kills: +10",
        "Add Kills: +100",
        "Set Prestige: +1",
        "Reset Stats",
        "Back"
    ];

    self.subMenus["Visual Mods"] = [
        "Night Mode",
        "Rainbow Vision",
        "Toggle HUD Glow",
        "Back"
    ];

    self.subMenus["Teleport Menu"] = [
        "Save Current Location",
        "Teleport to Saved",
        "Teleport to Me (host)",
        "Back"
    ];

    // HUD & input threads
    self thread menu_input_handler();
    self thread menu_hud_updater();
}

// ===================================================================
// INPUT HANDLER (per-player)
// Replace your input system to call "notify(self, "menu_input", action)"
// Valid actions: "open", "up", "down", "select", "back"
// ===================================================================
menu_input_handler()
{
    for (;;)
    {
        self waittill("menu_input", action);

        switch(action)
        {
            case "open":   self thread menu_toggle(); break;
            case "up":     self thread menu_scroll(-1); break;
            case "down":   self thread menu_scroll(1); break;
            case "select": self thread menu_select(); break;
            case "back":   self thread menu_back(); break;
        }
    }
}

// ===================================================================
// MENU CORE
// ===================================================================
menu_toggle()
{
    self.menuOpen = !self.menuOpen;

    if (self.menuOpen)
    {
        self.menuLayer = 0;
        self.menuIndex = 0;
        self.currentMenu = self.mainMenu;
        self.menuHistory = [];
        self.targetPlayer = undefined;
        self.playerListIndex = 0;
        self thread build_menu_hud();
        self thread update_menu_hud();
        self playSound("ui_menu_open");
    }
    else
    {
        self playSound("ui_menu_close");
        self thread destroy_menu_hud();
    }
}

menu_scroll(dir)
{
    if (!self.menuOpen) return;

    // special-case when viewing dynamic player list (layer 1 & currentMenu is "Player List")
    if (self.menuLayer == 1 && self.menuHistory[self.menuLayer-1] == "PlayerListMode")
    {
        // navigate player list
        players = get_active_players();
        if (players.size == 0) return;
        self.playerListIndex = ((self.playerListIndex + dir + players.size) % players.size);
        self playSound("ui_scroll");
        self thread update_menu_hud();
        return;
    }

    total = self.currentMenu.size;
    self.menuIndex = ((self.menuIndex + dir + total) % total);
    self playSound("ui_scroll");
    self thread update_menu_hud();
}

menu_back()
{
    if (!self.menuOpen) return;

    if (self.menuLayer > 0)
    {
        // if we were in PlayerListMode, clean state
        if (isdefined(self.menuHistory[self.menuLayer-1]) && self.menuHistory[self.menuLayer-1] == "PlayerListMode")
        {
            self.targetPlayer = undefined;
            self.playerListIndex = 0;
        }

        // pop history
        self.menuLayer--;
        prev = self.menuHistory[self.menuLayer];
        if (isdefined(prev) && prev != "PlayerListMode")
            self.currentMenu = prev;
        else
            self.currentMenu = self.mainMenu;
        self.menuHistory[self.menuLayer] = undefined;
        self.menuIndex = 0;
        self playSound("ui_back");
        self thread update_menu_hud();
    }
    else
    {
        self thread menu_toggle(); // close menu
    }
}

// ===================================================================
// SELECTION HANDLING
// ===================================================================
menu_select()
{
    if (!self.menuOpen) return;

    // Player list mode special-case
    if (self.menuLayer == 1 && isdefined(self.menuHistory[self.menuLayer-1]) && self.menuHistory[self.menuLayer-1] == "PlayerListMode")
    {
        players = get_active_players();
        if (players.size == 0) return;
        self.targetPlayer = players[self.playerListIndex];
        // Open actions for target player (sub-submenu)
        self.menuHistory[self.menuLayer] = self.currentMenu;
        self.menuLayer++;
        self.currentMenu = [
            "Give Weapon To Player",
            "Teleport Player To Me",
            "Set Player XP +1000",
            "Set Player Kills +10",
            "Kick Player (placeholder)",
            "Back"
        ];
        self.menuIndex = 0;
        self playSound("ui_select");
        self thread update_menu_hud();
        return;
    }

    sel = self.currentMenu[self.menuIndex];

    // If selection corresponds to a defined submenu name, navigate into it
    if (isdefined(self.subMenus[sel]))
    {
        self.menuHistory[self.menuLayer] = self.currentMenu;
        self.menuLayer++;
        self.currentMenu = self.subMenus[sel];
        self.menuIndex = 0;
        self playSound("ui_select");
        self thread update_menu_hud();
        return;
    }

    // Handle special main menu items
    if (self.menuLayer == 0)
    {
        switch(sel)
        {
            case "Save Config":
                self thread menu_save_config();
                return;
            case "Load Config":
                self thread menu_load_config();
                return;
            case "Player Mods":
                // Enter Player List Mode (dynamic)
                self.menuHistory[self.menuLayer] = "PlayerListMode"; // marker
                self.menuLayer++;
                self.currentMenu = []; // will be ignored; we use playerListIndex instead
                self.menuIndex = 0;
                self.playerListIndex = 0;
                self playSound("ui_select");
                self thread update_menu_hud();
                return;
            case "Close Menu":
                self thread menu_toggle();
                return;
            default:
                // fallthrough to below generic handlers
                break;
        }
    }

    // Generic action handlers across submenus
    // HOST TOGGLES
    if (sel == "God Mode")
    {
        self.godMode = !self.godMode;
        if (self.godMode) self iprintlnbold("God Mode: ON"); else self iprintlnbold("God Mode: OFF");
        self thread update_menu_hud();
        return;
    }
    if (sel == "Unlimited Ammo")
    {
        self.unlimitedAmmo = !self.unlimitedAmmo;
        self iprintlnbold("Unlimited Ammo: " + (self.unlimitedAmmo ? "ON" : "OFF"));
        self thread update_menu_hud();
        return;
    }
    if (sel == "UFO Mode")
    {
        self.ufo = !self.ufo;
        self iprintlnbold("UFO Mode: " + (self.ufo ? "ON" : "OFF"));
        self thread update_menu_hud();
        return;
    }
    if (sel == "Noclip")
    {
        self.noclip = !self.noclip;
        self iprintlnbold("Noclip: " + (self.noclip ? "ON" : "OFF"));
        self thread update_menu_hud();
        return;
    }
    if (sel == "Super Speed")
    {
        self.superSpeed = !self.superSpeed;
        self iprintlnbold("Super Speed: " + (self.superSpeed ? "ON" : "OFF"));
        self thread update_menu_hud();
        return;
    }
    if (sel == "Infinite Points")
    {
        self.infinitePoints = !self.infinitePoints;
        self iprintlnbold("Infinite Points: " + (self.infinitePoints ? "ON" : "OFF"));
        self thread update_menu_hud();
        return;
    }

    // WEAPON ACTIONS
    if (sel == "Give Ray Gun")
    {
        self giveWeapon("ray_gun");
        self iprintlnbold("Ray Gun given!");
        return;
    }
    if (sel == "Give PPSH")
    {
        self giveWeapon("mp40");
        self iprintlnbold("PPSH given!");
        return;
    }
    if (sel == "Give All Weapons")
    {
        self giveAllWeapons();
        self iprintlnbold("All weapons given!");
        return;
    }
    if (sel == "Clear Weapons")
    {
        self takeAllWeapons();
        self iprintlnbold("Weapons cleared!");
        return;
    }

    // FUN
    if (sel == "Third Person")
    {
        self setClientDvar("cg_thirdPerson", "1");
        self iprintlnbold("Third person enabled");
        return;
    }
    if (sel == "Explosive Bullets")
    {
        self iprintlnbold("Explosive bullets enabled (placeholder)");
        // implement logic hooking bullet impact callbacks etc.
        return;
    }
    if (sel == "Gravity Gun")
    {
        self iprintlnbold("Gravity Gun toggled (placeholder)");
        return;
    }
    if (sel == "Rainbow HUD")
    {
        self.rainbowHud = !self.rainbowHud;
        self iprintlnbold("Rainbow HUD: " + (self.rainbowHud ? "ON" : "OFF"));
        return;
    }

    // TELEPORT
    if (sel == "Save Current Location")
    {
        self.savedPos = self.origin;
        self iprintlnbold("Location saved!");
        return;
    }
    if (sel == "Teleport to Saved")
    {
        if (isdefined(self.savedPos))
        {
            self.origin = self.savedPos;
            self iprintlnbold("Teleported to saved location!");
        }
        else
        {
            self iprintlnbold("No saved location!");
        }
        return;
    }
    if (sel == "Teleport to Me (host)")
    {
        // Teleport host to self — placeholder for host teleport logic
        self iprintlnbold("Teleported host to you (placeholder)");
        return;
    }

    // STAT EDITOR
    if (sel == "Set XP: +1000")
    {
        self addXP(1000);
        self iprintlnbold("+1000 XP applied");
        return;
    }
    if (sel == "Set XP: +10000")
    {
        self addXP(10000);
        self iprintlnbold("+10000 XP applied");
        return;
    }
    if (sel == "Set XP: MAX")
    {
        self setXP(2147483647);
        self iprintlnbold("XP set to MAX");
        return;
    }
    if (sel == "Add Kills: +10")
    {
        self addKills(10);
        self iprintlnbold("+10 Kills applied");
        return;
    }
    if (sel == "Add Kills: +100")
    {
        self addKills(100);
        self iprintlnbold("+100 Kills applied");
        return;
    }
    if (sel == "Set Prestige: +1")
    {
        self addPrestige(1);
        self iprintlnbold("Prestige +1 applied");
        return;
    }
    if (sel == "Reset Stats")
    {
        self resetStats();
        self iprintlnbold("Stats reset (placeholder)");
        return;
    }

    // VISUALS
    if (sel == "Night Mode")
    {
        self iprintlnbold("Night mode toggled (placeholder)");
        return;
    }
    if (sel == "Rainbow Vision")
    {
        self iprintlnbold("Rainbow vision toggled (placeholder)");
        return;
    }
    if (sel == "Toggle HUD Glow")
    {
        self.hudGlow = !self.hudGlow;
        self iprintlnbold("HUD Glow: " + (self.hudGlow ? "ON" : "OFF"));
        return;
    }

    // GENERIC Back handling
    if (sel == "Back")
    {
        self thread menu_back();
        return;
    }

    // If we reach here but selection not matched, echo
    self iprintlnbold("Selected: " + sel);
    self thread update_menu_hud();
}

// ===================================================================
// SAVE / LOAD CONFIG
//  - Save current toggle state into level.menuConfigs[configSlot]
//  - Load applies saved toggles
// ===================================================================
menu_save_config()
{
    cfg = [];
    cfg.godMode = self.godMode;
    cfg.unlimitedAmmo = self.unlimitedAmmo;
    cfg.noclip = self.noclip;
    cfg.ufo = self.ufo;
    cfg.superSpeed = self.superSpeed;
    cfg.infinitePoints = self.infinitePoints;
    cfg.rainbowHud = self.rainbowHud;
    cfg.hudGlow = self.hudGlow;
    cfg.savedPos = self.savedPos;
    // store it globally on the level while map is loaded
    level.menuConfigs[self.configSlot] = cfg;
    self iprintlnbold("Menu config saved.");
    self thread update_menu_hud();
}

menu_load_config()
{
    cfg = level.menuConfigs[self.configSlot];
    if (!isdefined(cfg))
    {
        self iprintlnbold("No config saved.");
        return;
    }
    self.godMode = cfg.godMode;
    self.unlimitedAmmo = cfg.unlimitedAmmo;
    self.noclip = cfg.noclip;
    self.ufo = cfg.ufo;
    self.superSpeed = cfg.superSpeed;
    self.infinitePoints = cfg.infinitePoints;
    self.rainbowHud = cfg.rainbowHud;
    self.hudGlow = cfg.hudGlow;
    self.savedPos = cfg.savedPos;
    self iprintlnbold("Menu config loaded.");
    self thread update_menu_hud();
}

// ===================================================================
// HUD SYSTEM (per-player)
//  - Title hud
//  - Menu rows
//  - Animated background rect + glow
// ===================================================================
build_menu_hud()
{
    // Top glow/title
    self.menuBg = newHudElem();
    self.menuBg alignx = "center";
    self.menuBg aligny = "top";
    self.menuBg.x = 0;
    self.menuBg.y = 40;
    self.menuBg.horzAlign = "center";
    self.menuBg.vertAlign = "top";
    self.menuBg.foreground = false;
    self.menuBg.alpha = 0.8;
    self.menuBg setShader("white"); // placeholder - replace shader if desired
    self.menuBg scale = (600, 220); // not a real API in all engines — treat as conceptual; replace with proper sizing if needed

    // Title hud elem
    self.menuTitleHud = newHudElem();
    self.menuTitleHud.x = 180;
    self.menuTitleHud.y = 60;
    self.menuTitleHud.fontScale = 2.0;
    self.menuTitleHud.foreground = true;
    self.menuTitleHud.alpha = 1;
    self.menuTitleHud setText("Mod Menu");

    // Rows
    self.menuHudElems = [];
    baseY = 110;
    for (i = 0; i < self.visibleWindowSize; i++)
    {
        hud = newHudElem();
        hud.x = 150;
        hud.y = baseY + (i * 20);
        hud.fontScale = 1.2;
        hud.foreground = true;
        hud.alpha = 1;
        self.menuHudElems[i] = hud;
    }

    // Glow overlay
    self.menuGlow = newHudElem();
    self.menuGlow.x = 180;
    self.menuGlow.y = 50;
    self.menuGlow.fontScale = 1;
    self.menuGlow.foreground = true;
    self.menuGlow.alpha = 0.5;
    self.menuGlow setText("^7"); // placeholder, we will mod color

    // Start background animation thread
    self thread menu_bg_animator();
}

update_menu_hud()
{
    if (!self.menuOpen) return;

    // Title text depends on layer
    if (self.menuLayer == 0)
        title = "Main Menu";
    else if (self.menuLayer == 1 && isdefined(self.menuHistory[self.menuLayer-1]) && self.menuHistory[self.menuLayer-1] == "PlayerListMode")
        title = "Player List";
    else
        title = (isdefined(self.menuHistory[self.menuLayer-1]) && self.menuHistory[self.menuLayer-1] == "PlayerListMode" ? "Player Actions" : "Menu");

    self.menuTitleHud setText("^2" + title);

    // When in PlayerListMode, build dynamic list of players
    if (self.menuLayer == 1 && isdefined(self.menuHistory[self.menuLayer-1]) && self.menuHistory[self.menuLayer-1] == "PlayerListMode")
    {
        players = get_active_players();
        total = players.size;
        if (total == 0)
        {
            for (i = 0; i < self.visibleWindowSize; i++)
                self.menuHudElems[i] setText("  (no players)");
            return;
        }

        // center on playerListIndex
        window = self.visibleWindowSize;
        middle = int(window / 2);
        start = self.playerListIndex - middle;
        for (i = 0; i < window; i++)
        {
            idx = ((start + i) % total + total) % total;
            p = players[idx];
            name = player_display_name(p);
            prefix = (idx == self.playerListIndex) ? "^3> " : "  ";
            self.menuHudElems[i] setText(prefix + name);
        }
        return;
    }

    // Normal menu rendering
    total = self.currentMenu.size;
    window = self.visibleWindowSize;
    middle = int(window / 2);
    start = self.menuIndex - middle;

    for (i = 0; i < window; i++)
    {
        idx = ((start + i) % total + total) % total;
        txt = self.currentMenu[idx];
        // show toggles inline when relevant
        suffix = "";
        if (txt == "God Mode") suffix = " [" + (self.godMode ? "ON" : "OFF") + "]";
        if (txt == "Unlimited Ammo") suffix = " [" + (self.unlimitedAmmo ? "ON" : "OFF") + "]";
        if (txt == "No
