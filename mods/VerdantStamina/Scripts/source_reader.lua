-- Bounded native reads, called only from the existing game-thread scheduler.
-- Never applies/removes effects or writes attributes. Do not use BaseValue as
-- the permanent/temporary distinction: Windrose stat upgrades are modifiers too.
local Model=require("source_model")
local M={}
local function valid(o) return o and o:IsValid() end
local function text(v)
    if type(v)=="string" then return v end
    return v:ToString()
end
local function each(array,limit,fn)
    -- UFunction return arrays are copied into ordinary Lua tables by UE4SS;
    -- reflected UPROPERTY arrays remain TArray wrappers. Support both paths.
    if type(array)=="table" and not array.GetArrayNum then
        assert(#array<=limit,"Oversized returned effect array")
        for _,value in ipairs(array) do fn(value) end
        return
    end
    assert(array and array:GetArrayNum()<=limit,"Invalid or oversized native effect array")
    array:ForEach(function(_,param)
        fn(param:get())
        -- UE4SS 4.0 iterator callbacks must return nil, never false.
    end)
end
local function library()
    local o=StaticFindObject("/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary")
    assert(valid(o),"AbilitySystemBlueprintLibrary unavailable")
    return o
end

function M.read(widget,maximum)
    local controller=widget:GetOwningPlayer()
    if not valid(controller) then
        local gameplay=StaticFindObject("/Script/Engine.Default__GameplayStatics")
        assert(valid(gameplay),"GameplayStatics unavailable")
        controller=gameplay:GetPlayerController(widget,0)
    end
    assert(valid(controller),"Local controller unavailable")
    local player=controller.PlayerState
    assert(valid(player),"Local player state unavailable")
    local attributes=player.R5AttributeSet
    assert(valid(attributes),"Local attribute set unavailable")
    local api=library()
    local asc=api:GetAbilitySystemComponent(player)
    assert(valid(asc),"Local AbilitySystemComponent unavailable")
    local endurance,stamina=attributes.Endurance,attributes.MaxStamina
    assert(math.abs(stamina.CurrentValue-maximum)<0.1,"Widget and GAS maximum disagree")
    local snapshot={maximum=maximum,endurance=endurance.CurrentValue,
        endurance_base=endurance.BaseValue,maximum_base=stamina.BaseValue,effects={},
        formula=require("game_data").endurance_formula()}
    -- Read the ASC-owned effect specs directly. UE4SS 4.0's returned arrays of
    -- struct handles produced invalid struct metadata in this build; passing
    -- those wrappers to another UFunction is unsafe. These are stable native
    -- UPROPERTY arrays on the already-owned ASC, read in one game-thread turn.
    local active_effects=asc.ActiveGameplayEffects.GameplayEffects_Internal
    each(active_effects,512,function(active)
        local spec=active.Spec
        local definition=spec.Def
        assert(valid(definition),"Expired active gameplay effect")
        local effect={name=definition:GetFullName(),duration=spec.Duration,modifiers={}}
        local magnitudes={}
        each(spec.Modifiers,64,function(evaluated)
            magnitudes[#magnitudes+1]=evaluated.EvaluatedMagnitude
        end)
        local stacks=spec.StackCount
        assert(type(stacks)=="number" and stacks>=1,"Invalid effect stack count")
        local index=0
        each(definition.Modifiers,64,function(mod)
            index=index+1
            local name=text(mod.Attribute.AttributeName)
            if name=="Endurance" or name=="MaxStamina" then
                assert(type(magnitudes[index])=="number","Missing evaluated modifier")
                effect.modifiers[#effect.modifiers+1]={attribute=name,operation=mod.ModifierOp,
                    magnitude=magnitudes[index]*stacks}
            end
        end)
        if #effect.modifiers>0 then snapshot.effects[#snapshot.effects+1]=effect end
    end)
    local result=Model.resolve(snapshot)
    result.player_address=player:GetAddress()
    return result
end

return M
