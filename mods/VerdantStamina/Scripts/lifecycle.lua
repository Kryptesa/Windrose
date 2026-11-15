-- One class-specific construction notification for the lifetime of this mod.
-- UE4SS 4.0 dispatches loading-thread notifications back onto the game thread.
-- The callback only queues the UObject; UMG reads/construction wait for our
-- already-existing native frame loop, after the game's initialization returns.
local M={}
local key="VerdantStamina_Lifecycle"
local broker=rawget(_G,key)
if not broker then
    broker={registered=false,pending={},frame=0}
    rawset(_G,key,broker)
end
local class="/Game/UI/HUD/CharacterPanel/StaminaRing/WBP_StaminaRing.WBP_StaminaRing_C"

function M.start(log)
    broker.active=true
    broker.pending={}
    if broker.registered then return true end
    local ok,err=pcall(function()
        NotifyOnNewObject(class,function(widget)
            if broker.active and widget and widget:IsValid()
                and not widget:GetFullName():find("Default__",1,true) then
                broker.pending[widget:GetAddress()]={widget=widget,first_frame=broker.frame}
            end
            -- No return: keep this single notification registered across reloads.
        end)
    end)
    if ok then
        broker.registered=true
        log("HUD construction notification registered; game-thread queue enabled")
    else log("HUD construction notification unavailable; periodic recovery retained: "..tostring(err)) end
    return ok
end

function M.stop()
    broker.active=false
    broker.pending={}
end

function M.drain(ready)
    broker.frame=broker.frame+1
    for address,item in pairs(broker.pending) do
        local age=broker.frame-item.first_frame
        if not item.widget:IsValid() or age>120 or ready(item.widget,age) then
            broker.pending[address]=nil
        end
    end
end

return M
