-- Exercise the native boundary with Unreal-shaped arrays/struct wrappers.
-- These fixtures check marshalling contracts, not whether the engine exports work.
local function object(t)
    function t:IsValid() return true end
    function t:GetAddress() return 42 end
    return t
end
local function array(values)
    return {GetArrayNum=function() return #values end,ForEach=function(_,callback)
        for i,value in ipairs(values) do
            local result=callback(i,{get=function() return value end})
            assert(result==nil,'UE4SS iterator callbacks must return nil')
        end
    end}
end
local formula={AttributePointValue=3,AttributeUpperLimit=176,EffectivenessC1=1.53,
    EffectivenessC2=1.1475,EffectivenessC3=0.765,PivotValue1=20,PivotValue2=40}
local function modifier(name,magnitude)
    local attr={AttributeName={ToString=function() return name end}}
    return {Attribute=attr,ModifierOp=0,magnitude=magnitude,name=name}
end
local function effect(name,duration,mods)
    local o=object({name=name,duration=duration,mods=mods,Modifiers=array(mods)})
    function o:GetFullName() return self.name end
    local evaluated={}
    for _,mod in ipairs(mods) do evaluated[#evaluated+1]={EvaluatedMagnitude=mod.magnitude} end
    return {definition=o,Spec={Def=o,Duration=duration,Modifiers=array(evaluated),StackCount=1}}
end
local effects={effect('Stat',-1,{modifier('Endurance',45)}),
    effect('Necklace',-1,{modifier('Endurance',15)}),
    effect('Coffee',1800,{modifier('Endurance',20)}),
    effect('Fruit',420,{modifier('MaxHealth',160),modifier('MaxStamina',160)}),
    effect('Native Endurance calculator',-1,{modifier('MaxStamina',252.45)}),
    effect('Talent',-1,{modifier('MaxStamina',50)})}
local asc=object({ActiveGameplayEffects={GameplayEffects_Internal=array(effects)}})
function asc:GetActiveEffects() error('returned struct handles must not be used') end
function asc:GetGameplayEffectMagnitude() error('native specs already hold evaluated values') end
local attrs=object({Endurance={BaseValue=0,CurrentValue=80},MaxStamina={BaseValue=150,CurrentValue=612.45}})
local player=object({R5AttributeSet=attrs})
local controller=object({PlayerState=player})
local widget=object({GetOwningPlayer=function() return controller end})
local api=object({})
function api:GetAbilitySystemComponent(actor) assert(actor==player);return asc end
function StaticFindObject(path)
    if path=='/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary' then return api end
    if path:find('BP_HeroAttrbiuteCalc_Endurance_MaxStamina',1,true) then
        return object({GetCDO=function() return {FormulaConfig=formula} end})
    end
    error('unexpected object lookup: '..path)
end
local reader=require('source_reader')
local result=reader.read(widget,612.45)
assert(math.abs(result.permanent_maximum-406.55)<1e-6)
assert(math.abs(result.temporary_maximum-205.9)<1e-6)
assert(result.temporary_direct_stamina==160 and #result.effects==2)
asc.ActiveGameplayEffects.GameplayEffects_Internal=effects
assert(math.abs(reader.read(widget,612.45).temporary_maximum-205.9)<1e-6)
-- Separate modifiers of the same attribute keep their own evaluated values.
effects[4].definition.Modifiers=array({modifier('MaxStamina',160),modifier('MaxStamina',10)})
effects[4].Spec.Modifiers=array({{EvaluatedMagnitude=160},{EvaluatedMagnitude=10}})
attrs.MaxStamina.CurrentValue=622.45
assert(math.abs(reader.read(widget,622.45).temporary_direct_stamina-170)<1e-6)
print('Native source adapter contracts passed')
