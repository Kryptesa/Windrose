-- Opt-in, direct reads only. Requiring this file has no runtime side effects.
-- Metadata iterators failed after their first callback in the tested UE4SS build.
-- No function/property enumeration, UObject scans, asset loads or gameplay calls.
local diagnostics = {}
local pending = false
local PREFIX = '[VerdantStamina diagnostics] '
local FORMULA_FIELDS = {
    'AttributePointValue', 'AttributeUpperLimit',
    'EffectivenessC1', 'EffectivenessC2', 'EffectivenessC3',
    'PivotValue1', 'PivotValue2',
}

local function log(message)
    print(PREFIX .. tostring(message) .. '\n')
end

local function attempt(label, callback)
    local ok, result = pcall(callback)
    if not ok then log(label .. ': ' .. tostring(result)) end
    return ok, result
end

local function valid(object)
    if object == nil then return false end
    local ok, result = pcall(function() return object:IsValid() end)
    return ok and result == true
end

local function find(path)
    local ok, object = attempt('lookup ' .. path, function()
        return StaticFindObject(path)
    end)
    if ok and valid(object) then return object end
    log('not loaded: ' .. path)
    return nil
end

local function inspect_formula(path, label)
    local class = find(path)
    if not class then return end
    attempt(label, function()
        local cdo = class:GetCDO()
        if not valid(cdo) then log(label .. ': no existing CDO'); return end
        log(label .. ' CDO: ' .. tostring(cdo:GetFullName()))
        local config = cdo.FormulaConfig
        if not valid(config) then log(label .. ': FormulaConfig unavailable'); return end
        -- These seven scalar names are confirmed in the local executable.
        for _, field in ipairs(FORMULA_FIELDS) do
            local ok, value = attempt(label .. '.FormulaConfig.' .. field, function()
                return config[field]
            end)
            if ok then log('  FormulaConfig.' .. field .. ' = ' .. tostring(value)) end
        end
    end)
end

local function inspect_function(path)
    local func = find(path)
    if not func then return end
    attempt('function metadata ' .. path, function()
        log('function ' .. tostring(func:GetFullName())
            .. ' flags=' .. tostring(func:GetFunctionFlags()))
    end)
end

local function inspect_now(options)
    log('begin direct read-only inspection')
    inspect_formula('/Script/R5GAS.R5ModMagCalc_HeroAttributeLinear',
        'native calculator')
    local bp_path = '/Game/Gameplay/Character/Common/GameplayEffects/'
        .. 'HeroAttributesCalculator/BP_HeroAttrbiuteCalc_Endurance_MaxStamina'
    inspect_formula(bp_path .. '.BP_HeroAttrbiuteCalc_Endurance_MaxStamina_C',
        'Endurance MaxStamina calculator')
    inspect_function('/Script/R5.R5CharacterUIModel:GetCurrentStamina')
    inspect_function('/Script/R5.R5CharacterUIModel:GetMaxStamina')
    inspect_function('/Script/UMG.UserWidget:GetWidgetFromName')
    if valid(options.widget) then attempt('widget identity', function()
        log('widget: ' .. tostring(options.widget:GetFullName()))
        local controller=options.widget:GetOwningPlayer()
        if not valid(controller) then
            local gameplay=StaticFindObject('/Script/Engine.Default__GameplayStatics')
            if valid(gameplay) then controller=gameplay:GetPlayerController(options.widget,0) end
        end
        if not valid(controller) then log('local controller unavailable');return end
        local player_state=controller.PlayerState
        if not valid(player_state) then return end
        local attributes=player_state.R5AttributeSet
        if not valid(attributes) then return end
        for _,field in ipairs({'Stamina','MaxStamina','Endurance'}) do
            attempt('GAS '..field,function()
                local attribute=attributes[field]
                log('  GAS.'..field..'.BaseValue='..tostring(attribute.BaseValue)
                    ..' CurrentValue='..tostring(attribute.CurrentValue))
            end)
        end
    end) end
    log('inspection complete; no gameplay functions invoked')
end

-- Explicit opt-in. Optional {widget=knownRing} also prints that widget's identity.
-- Game-thread work is deferred, and concurrent queued requests are coalesced.
-- Use this direct entry point when already in the native game-thread loop.
function diagnostics.inspect_now(options)
    return inspect_now(options or {})
end

function diagnostics.inspect(options)
    if pending then return false, 'inspection already queued' end
    pending = true
    local ok, err = pcall(function()
        ExecuteInGameThread(function()
            attempt('inspection', function() inspect_now(options or {}) end)
            pending = false
        end)
    end)
    if not ok then
        pending = false
        log('queue failed: ' .. tostring(err))
        return false, err
    end
    return true
end

return diagnostics
