-- Read the initial stamina curve, not the player's already-upgraded maximum.
-- UE4SS 4.0 stores primitive out parameters under their reflected field names.
local M={}
local formula
function M.endurance_formula()
    if formula then return formula end
    local path="/Game/Gameplay/Character/Common/GameplayEffects/HeroAttributesCalculator/"
        .."BP_HeroAttrbiuteCalc_Endurance_MaxStamina.BP_HeroAttrbiuteCalc_Endurance_MaxStamina_C"
    local class=StaticFindObject(path)
    if not class or not class:IsValid() then class=LoadAsset(path) end
    assert(class and class:IsValid(),"Endurance calculator unavailable")
    local config=class:GetCDO().FormulaConfig
    local out={}
    for _,key in ipairs({"AttributePointValue","AttributeUpperLimit","EffectivenessC1",
                          "EffectivenessC2","EffectivenessC3","PivotValue1","PivotValue2"}) do
        out[key]=config[key]
        assert(type(out[key])=="number","Cannot read Endurance formula: "..key)
    end
    formula=out
    return formula
end
function M.base_capacity()
    local library=StaticFindObject("/Script/Engine.Default__DataTableFunctionLibrary")
    assert(library and library:IsValid(), "DataTableFunctionLibrary unavailable")
    local path="/Game/Gameplay/Character/Player/Parameters/CT_CharactersAttributes.CT_CharactersAttributes"
    local table=StaticFindObject(path)
    if not table or not table:IsValid() then table=LoadAsset(path) end
    assert(table and table:IsValid(), "Initial character curve unavailable")
    local result,value={},{}
    library:EvaluateCurveTableRow(table,FName("Hero_MaxStamina"),1,result,value,"VerdantStamina")
    local base=value.OutXY
    assert(type(base)=="number" and base>0 and base<math.huge, "Invalid base curve value")
    return base
end
return M
