-- Stable scheduler. Game-specific code can be reloaded with F10 or reload.txt.
local source=debug.getinfo(1,"S").source:gsub("^@", "")
local directory=source:match("^(.*[\\/])") or ""
local marker_path=directory.."reload.txt"
local app, last_time, next_marker = nil, os.clock(), 0
local reload_requested=true
local toggle_requested,diagnostics_requested=false,false
local function marker()
    local file=io.open(marker_path,"r")
    if not file then return "" end
    local value=file:read("*a");file:close();return value
end
local last_marker=marker()
local function log(s) print("[VerdantStamina] "..s.."\n") end
local function reload()
    if app then pcall(app.stop) end
    app=nil
    for _, name in ipairs({"app","config","core","renderer","diagnostics","game_data"}) do package.loaded[name]=nil end
    -- UE4SS has a second cache of compiled loader functions. Clearing only
    -- package.loaded re-executes the old loader even after the file changes.
    -- Invalidate this mod's script files only; leave shared/other mods intact.
    if type(ue4ss_loaded_modules)=="table" then
        local prefix=directory:gsub("\\","/"):lower()
        if prefix~="" then
            for path in pairs(ue4ss_loaded_modules) do
                if type(path)=="string" and path:gsub("\\","/"):lower():sub(1,#prefix)==prefix then
                    ue4ss_loaded_modules[path]=nil
                end
            end
        end
    end
    local ok,result=pcall(require,"app")
    if ok then app=result;log("0.1.0-alpha.4 ready; renderer="..tostring(app.revision).."; F8 toggle / F9 diagnostics / F10 reload")
    else log("Could not load mod; original HUD retained. "..tostring(result)) end
    reload_requested=false
end

-- UE4SS async Lua APIs share the registry with the game-thread state. Even a
-- LoopAsync callback which only queues work can race native UMG marshalling.
-- One persistent native game-thread loop avoids that boundary entirely.
LoopInGameThreadAfterFrames(1,function()
    local now=os.clock()
    if now>=next_marker then
        next_marker=now+1
        local value=marker()
        if value~=last_marker then last_marker=value;reload_requested=true end
    end
    local delta=math.max(0,now-last_time);last_time=now
    if reload_requested then reload() end
    if toggle_requested then
        toggle_requested=false
        if app then app.toggle() end
    end
    if diagnostics_requested then
        diagnostics_requested=false
        local ok,err=pcall(function() require("diagnostics").inspect_now() end)
        if not ok then log("Diagnostics: "..tostring(err)) end
    end
    if app then
        local ok,err=pcall(app.frame,delta,now)
        if not ok then
            pcall(app.stop);app=nil
            log("Stopped; restored original HUD. "..tostring(err))
        end
    end
end)

RegisterKeyBind(0x77,function() toggle_requested=true end)
RegisterKeyBind(0x78,function() diagnostics_requested=true end)
RegisterKeyBind(0x79,function() reload_requested=true end)
log("Scheduler loaded")
