-- Read-only accounting. All amounts originate in a native snapshot, not item names.
local M={}
local function finite(v) return type(v)=="number" and v==v and math.abs(v)<math.huge end
local function near(a,b) return math.abs(a-b)<=math.max(0.06,math.abs(b)*0.0001) end

function M.endurance_bonus(value,f)
    assert(finite(value),"Invalid Endurance")
    for _,k in ipairs({"AttributePointValue","AttributeUpperLimit","EffectivenessC1",
                       "EffectivenessC2","EffectivenessC3","PivotValue1","PivotValue2"}) do
        assert(finite(f[k]),"Invalid native formula field: "..k)
    end
    local a,b,c=f.EffectivenessC1,f.EffectivenessC2,f.EffectivenessC3
    return f.AttributePointValue*math.max(0,math.min(a*value,
        b*value+(a-b)*f.PivotValue1,
        c*value+(a-b)*f.PivotValue1+(b-c)*f.PivotValue2,f.AttributeUpperLimit))
end

function M.resolve(snapshot)
    for _,k in ipairs({"maximum","endurance","endurance_base","maximum_base"}) do
        assert(finite(snapshot[k]),"Invalid native attribute: "..k)
    end
    assert(snapshot.maximum>0,"Invalid native maximum")
    local endurance_sum,maximum_sum=snapshot.endurance_base,snapshot.maximum_base
    local temporary_endurance,temporary_direct=0,0
    local temporary_effects={}
    for _,effect in ipairs(snapshot.effects) do
        assert(finite(effect.duration),"Missing native effect duration")
        local timed=effect.duration>0
        local relevant=false
        for _,mod in ipairs(effect.modifiers) do
            assert(mod.attribute=="Endurance" or mod.attribute=="MaxStamina","Unexpected attribute")
            assert(mod.operation==0,"Unsupported stamina modifier operation in "..effect.name)
            assert(finite(mod.magnitude),"Invalid native effect magnitude")
            if mod.attribute=="Endurance" then
                endurance_sum=endurance_sum+mod.magnitude
                if timed then temporary_endurance=temporary_endurance+mod.magnitude end
            else
                maximum_sum=maximum_sum+mod.magnitude
                if timed then temporary_direct=temporary_direct+mod.magnitude end
            end
            relevant=relevant or math.abs(mod.magnitude)>0.000001
        end
        if relevant then assert(effect.duration~=0,"Active effect duration is unavailable") end
        if timed and relevant then temporary_effects[#temporary_effects+1]=effect end
    end
    -- Suppressed, partially replicated, duplicate-attribute or unmodelled effects
    -- must not silently turn into a confidently labelled yellow reserve.
    assert(near(endurance_sum,snapshot.endurance),"Endurance effects do not reconcile with native total")
    assert(near(maximum_sum,snapshot.maximum),"MaxStamina effects do not reconcile with native total")
    local permanent_endurance=snapshot.endurance-temporary_endurance
    local bonus=M.endurance_bonus(snapshot.endurance,snapshot.formula)
    local permanent_bonus=M.endurance_bonus(permanent_endurance,snapshot.formula)
    local temporary=temporary_direct+bonus-permanent_bonus
    assert(finite(temporary),"Invalid temporary capacity")
    local permanent=snapshot.maximum-temporary
    assert(permanent>0,"Invalid permanent capacity")
    -- Negative timed penalties reduce the green pool; they are not a yellow bonus.
    local penalty=math.max(0,-temporary)
    return {
        verified=true,maximum=snapshot.maximum,
        permanent_maximum=math.min(snapshot.maximum,permanent),
        unpenalized_permanent_maximum=permanent,
        temporary_maximum=math.max(0,temporary),temporary_penalty=penalty,
        permanent_endurance=permanent_endurance,temporary_endurance=temporary_endurance,
        temporary_direct_stamina=temporary_direct,effects=temporary_effects,
    }
end

function M.partition(shown,sources)
    return math.min(shown,sources.permanent_maximum),math.max(0,shown-sources.permanent_maximum)
end

return M
