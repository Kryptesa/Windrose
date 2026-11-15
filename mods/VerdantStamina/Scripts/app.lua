-- Compatible with the already loaded stable scheduler: new source modules own
-- their package-cache invalidation here, so installation needs no game restart.
package.loaded["source_reader"],package.loaded["source_model"]=nil,nil
package.loaded["lifecycle"]=nil
local Config=require("config")
local Core=require("core")
local Renderer=require("renderer")
local Lifecycle=require("lifecycle")
Core.validate(Config)
local M={}
M.revision=Renderer.revision
local states={}
local enabled=Config.enabled
local next_discovery,diagnosed,boot_diagnosed=0,false,false
local base_checked=false
local function log(s) print("[VerdantStamina] "..s.."\n") end
local function valid(o) return o and o:IsValid() end
if enabled then Lifecycle.start(log) end

local function read_sources(state,maximum,time,model)
    if not Config.split_sources then return nil end
    local address=model:GetAddress()
    local due=not state.next_source or time>=state.next_source
        or state.source_maximum~=maximum or state.source_model~=address
    if due then
        state.next_source=time+Config.source_poll_seconds
        state.source_maximum,state.source_model=maximum,address
        local ok,result=pcall(function() return require("source_reader").read(state.widget,maximum) end)
        if ok then
            state.sources=result
            state.source_error=nil
            local signature=string.format("%.3f/%.3f/%.3f/%.3f/%.3f",result.maximum,
                result.permanent_maximum,result.temporary_maximum,result.permanent_endurance,result.temporary_endurance)
            if signature~=state.source_signature then
                state.source_signature=signature
                log(string.format("Sources verified total=%.3f permanent=%.3f temporary=%.3f permanentEndurance=%.3f temporaryEndurance=%.3f directTemporary=%.3f effects=%d",
                    maximum,result.permanent_maximum,result.temporary_maximum,result.permanent_endurance,
                    result.temporary_endurance,result.temporary_direct_stamina,#result.effects))
                for _,effect in ipairs(result.effects) do
                    for _,mod in ipairs(effect.modifiers) do
                        log(string.format("Temporary effect=%s duration=%.1f attribute=%s magnitude=%.3f",
                            effect.name,effect.duration,mod.attribute,mod.magnitude))
                    end
                end
            end
        else
            state.sources=nil
            if state.source_error~=tostring(result) then
                state.source_error=tostring(result)
                log((Config.visual_test_mode and "Native sources unavailable during visual test: "
                    or "Source split unavailable; original HUD retained: ")..state.source_error)
            end
        end
    end
    return state.sources
end

function M.stop()
    Lifecycle.stop()
    for _,s in pairs(states) do Renderer.destroy(s.renderer) end
    states={}
end

function M.toggle()
    M.stop();enabled=not enabled;next_discovery=0
    if enabled then Lifecycle.start(log) end
    log("Enabled="..tostring(enabled))
end

function M.frame(delta,time)
    if not enabled then return end
    if not boot_diagnosed then
        boot_diagnosed=true
        require("diagnostics").inspect_now({find_widget=false})
    end
    for key,state in pairs(states) do
        if not valid(state.widget) then
            Renderer.destroy(state.renderer);states[key]=nil
        end
    end
    Lifecycle.drain(function(widget,age)
        local model=widget.Model
        if valid(model) and Renderer.available(widget) then
            local address=widget:GetAddress()
            if not states[address] then
                states[address]={widget=widget,model=model}
                log(string.format("HUD creation event ready widget=%s pendingFrames=%d",tostring(address),age))
            end
            return true
        end
        return false
    end)
    if time>=next_discovery then
        next_discovery=time+1
        -- This build's Blueprint script UFunctions have Func=0: no Tick hook.
        -- Menus recreate nested HUD widgets while previous instances can remain
        -- valid. Reconcile this class once per second, never scan every frame.
        local seen={}
        for _,widget in ipairs(FindAllOf("WBP_StaminaRing_C") or {}) do
            if valid(widget) and not widget:GetFullName():find("Default__",1,true) then
                local model=widget.Model
                if valid(model) and Renderer.available(widget) then
                    local address=widget:GetAddress()
                    seen[address]=true
                    if not states[address] then states[address]={widget=widget,model=model} end
                end
            end
        end
        for address,state in pairs(states) do
            if not seen[address] then Renderer.destroy(state.renderer);states[address]=nil end
        end
    end
    for key,state in pairs(states) do
        local model=state.widget.Model
        if not valid(model) or not Renderer.available(state.widget) then
            Renderer.destroy(state.renderer);states[key]=nil
        else
            local current,maximum=model:GetCurrentStamina(),model:GetMaxStamina()
            if type(current)=="number" and type(maximum)=="number" and maximum>0 then
                local sources=read_sources(state,maximum,time,model)
                local actual_current,actual_maximum=current,maximum
                current,maximum,sources=Core.display_values(current,maximum,Config,sources)
                local permanent=sources and sources.permanent_maximum or maximum
                local temporary=sources and sources.temporary_maximum or 0
                if state.renderer and (state.maximum~=maximum or state.permanent~=permanent or state.temporary~=temporary
                    or not valid(state.model) or state.model:GetAddress()~=model:GetAddress()
                    or not Renderer.matches(state.renderer,state.widget)
                    or (Config.split_sources and not sources)) then
                    Renderer.destroy(state.renderer);state.renderer=nil;state.sample=nil
                end
                local sample=Core.sample(state.sample,current,maximum,delta,Config)
                if sample and (not Config.split_sources or sources) then
                    if not state.renderer then
                        if not base_checked then
                            base_checked=true
                            if Config.auto_base_capacity then
                                local ok,base=pcall(function() return require("game_data").base_capacity() end)
                                if ok then
                                    if Config.bonus_ring_capacity==Config.base_capacity then Config.bonus_ring_capacity=base end
                                    Config.base_capacity=base
                                    log("Initial stamina curve="..tostring(base))
                                else log("Using verified local base "..Config.base_capacity.."; curve read: "..tostring(base)) end
                            end
                        end
                        state.renderer=Renderer.create(state.widget,maximum,Config,sources)
                        state.maximum,state.model=maximum,model
                        state.permanent,state.temporary=permanent,temporary
                        if Config.visual_test_mode then
                            log(string.format("DISPLAY TEST active actual=%.3f/%.3f mapped=%.3f/%.3f permanent=%.3f temporary=%.3f; gameplay attributes unchanged",
                                actual_current,actual_maximum,current,maximum,permanent,temporary))
                        end
                        log(string.format("Bound renderer=%s current=%.3f max=%.3f base=%.3f bonus=%.3f rings=%d diameter=%.1f bonusWeights=%.1f/%.1f scale=%.2f surface=%s",tostring(Renderer.revision),current,maximum,Config.base_capacity,math.max(0,maximum-Config.base_capacity),#state.renderer.rings,(2*Config.radius+Config.base_thickness)*Config.ui_scale,Config.bonus_thickness*Config.ui_scale,Config.outer_bonus_thickness*Config.ui_scale,Config.ui_scale,Config.surface_style))
                        if not diagnosed then
                            diagnosed=true
                            require("diagnostics").inspect_now({widget=state.widget,find_widget=false})
                        end
                    end
                    Renderer.update(state.renderer,sample)
                    state.sample=sample
                end
            end
        end
    end
end

return M
