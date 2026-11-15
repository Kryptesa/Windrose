-- Pure display logic. Never writes gameplay attributes.
local M = {}

local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end
local function finite(x) return type(x) == "number" and x == x and math.abs(x) < math.huge end

function M.validate(c)
    assert(c.surface_style=="flat" or c.surface_style=="paint" or c.surface_style=="hatch","Invalid surface_style")
    for _, key in ipairs({"base_capacity", "bonus_ring_capacity", "radius", "base_thickness",
                           "bonus_thickness", "outer_bonus_thickness", "max_bonus_rings", "edge_softness", "ui_scale"}) do
        assert(finite(c[key]) and c[key] > 0, "Invalid " .. key)
    end
    assert(c.base_thickness < c.radius*2, "Base ring hole must remain open")
    assert(c.max_bonus_rings <= 12 and c.max_bonus_rings % 1 == 0, "max_bonus_rings must be an integer in [1,12]")
    assert(finite(c.new_ring_min_capacity) and c.new_ring_min_capacity>=0
        and c.new_ring_min_capacity<c.bonus_ring_capacity,"Invalid new-ring threshold")
    assert(finite(c.smoothing_seconds) and c.smoothing_seconds >= 0, "Invalid smoothing_seconds")
    assert(finite(c.ring_gap) and c.ring_gap >= 0, "Invalid ring_gap")
    assert(finite(c.critical_fraction) and c.critical_fraction >= 0 and c.critical_fraction <= 1, "Invalid critical_fraction")
    assert(finite(c.warning_start_fraction) and c.warning_start_fraction>c.critical_fraction and c.warning_start_fraction<=1,"Invalid warning_start_fraction")
    assert(finite(c.warning_smoothing_seconds) and c.warning_smoothing_seconds>=0,"Invalid warning_smoothing_seconds")
    for _, key in ipairs({"color", "critical_color", "background_color"}) do
        for _, channel in ipairs({"R", "G", "B", "A"}) do
            assert(finite(c[key][channel]) and c[key][channel] >= 0 and c[key][channel] <= 1, "Invalid " .. key .. "." .. channel)
        end
    end
    if c.split_sources then
        for _,key in ipairs({"source_poll_seconds","initial_ring_scale","temporary_ring_scale","temporary_group_gap"}) do
            assert(finite(c[key]) and c[key]>0,"Invalid "..key)
        end
        for _,channel in ipairs({"R","G","B","A"}) do
            assert(finite(c.temporary_color[channel]) and c.temporary_color[channel]>=0
                and c.temporary_color[channel]<=1,"Invalid temporary color")
        end
    end
    if c.visual_test_mode then
        assert(finite(c.test_permanent_capacity) and c.test_permanent_capacity>0,"Invalid test capacity")
        assert(finite(c.test_temporary_capacity) and c.test_temporary_capacity>0,"Invalid test reserve")
    end
    return c
end

function M.sample(state, current, maximum, dt, c)
    if not finite(current) or not finite(maximum) or maximum <= 0 then return nil end
    current = clamp(current, 0, maximum)
    dt = finite(dt) and clamp(dt, 0, 0.25) or 0
    local shown
    if not state or state.maximum ~= maximum or current == 0 or c.smoothing_seconds == 0 then
        shown = current
    else
        local alpha = 1 - math.exp(-math.log(10) * dt / c.smoothing_seconds)
        shown = clamp(state.shown + (current - state.shown) * alpha, 0, maximum)
        if math.abs(shown - current) < 0.0001 then shown = current end
    end
    local fraction=current/maximum
    local t=clamp((c.warning_start_fraction-fraction)/(c.warning_start_fraction-c.critical_fraction),0,1)
    local target=t*t*(3-2*t)
    local warning=target
    if state and state.warning and c.warning_smoothing_seconds>0 then
        local alpha=1-math.exp(-math.log(10)*dt/c.warning_smoothing_seconds)
        warning=state.warning+(target-state.warning)*alpha
        if math.abs(warning-target)<0.0001 then warning=target end
    end
    return {shown = shown, actual = current, maximum = maximum,warning=warning,
            critical = current / maximum <= c.critical_fraction}
end

function M.tint(sample,c)
    local amount=clamp(sample.warning or 0,0,1)
    local color={}
    for _,channel in ipairs({"R","G","B","A"}) do
        color[channel]=c.color[channel]+(c.critical_color[channel]-c.color[channel])*amount
    end
    return color
end

function M.rings(maximum, c)
    assert(finite(maximum) and maximum > 0, "Invalid maximum")
    local rings = {{start = 0, capacity = c.base_capacity,
                    available = math.min(maximum, c.base_capacity),
                    radius = c.radius, thickness = c.base_thickness,index=0}}
    local bonus = math.max(0, maximum - c.base_capacity)
    local capacity = c.bonus_ring_capacity
    local count = math.ceil(bonus / capacity - 1e-10)
    -- Avoid an almost invisible new arc without discarding its capacity: merge
    -- a sub-threshold remainder into the preceding ring. Drain is never snapped.
    local tiny=count>0 and bonus-(count-1)*capacity<c.new_ring_min_capacity
    if tiny then count=count-1 end
    local outer=c.radius+c.base_thickness/2
    for i = 1, count do
        local thickness=i==1 and c.bonus_thickness or c.outer_bonus_thickness
        rings[#rings + 1] = {
            start = c.base_capacity + (i - 1) * capacity,
            capacity = capacity,
            available = math.min(capacity, bonus - (i - 1) * capacity),
            radius = outer+c.ring_gap+thickness/2,
            thickness = thickness,index=i,
        }
        outer=outer+c.ring_gap+thickness
    end
    if tiny then
        local last=rings[#rings]
        local remainder=maximum-last.start-last.available
        last.available=last.available+remainder
        last.capacity=math.max(last.capacity,last.available)
    end
    return rings
end

function M.fill(ring, shown)
    return clamp((shown - ring.start) / ring.capacity, 0, ring.available / ring.capacity)
end

-- Asset indices/geometry remain unchanged. Groups use separate visual positions
-- and fill origins so a partial permanent ring never absorbs a temporary buff.
function M.layout(maximum,c,sources)
    local out={}
    local permanent=sources and sources.permanent_maximum or maximum
    local temporary=sources and sources.temporary_maximum or 0
    local green=M.rings(permanent,c)
    local scale=(sources and permanent<=c.base_capacity+0.001) and c.initial_ring_scale or 1
    local green_outer=0
    for _,ring in ipairs(green) do
        out[#out+1]={ring=ring,kind="permanent",x=0,y=0,scale=scale}
        green_outer=(ring.radius+ring.thickness/2)*scale
    end
    if temporary>0.001 then
        -- All timed bonuses share one complete yellow wheel, independent of
        -- the green 150-per-ring units. It can represent fruit plus Endurance.
        local ring=M.rings(c.base_capacity,c)[1]
        ring.capacity,ring.available=temporary,temporary
        local yellow_outer=(ring.radius+ring.thickness/2)*c.temporary_ring_scale
        local x=-green_outer-c.temporary_group_gap-yellow_outer
        out[#out+1]={ring=ring,kind="temporary",x=x,y=0,scale=c.temporary_ring_scale}
    end
    return out
end

function M.display_values(current,maximum,c,sources)
    if not c.visual_test_mode then return current,maximum,sources end
    local demo_max=c.test_permanent_capacity+c.test_temporary_capacity
    return clamp(current/maximum,0,1)*demo_max,demo_max,{
        display_test=true,verified=false,maximum=demo_max,
        permanent_maximum=c.test_permanent_capacity,temporary_maximum=c.test_temporary_capacity,
    }
end

-- Two clipped, continuously rotated half planes reveal a smooth ring texture.
-- No polygon segments or quantized image frames are used.
function M.arc_halves(fraction)
    fraction=clamp(fraction,0,1)
    return math.min(fraction,0.5)*360,math.max(fraction-0.5,0)*360
end

function M.arc_edges(fraction,inner_radius,softness)
    local right,left=M.arc_halves(fraction)
    local backoff=math.deg(softness*0.8/inner_radius)
    local ending=(fraction>0 and fraction<1) and (fraction<=0.5 and 1 or 2) or 0
    return {
        right=math.max(0,right-(ending==1 and backoff or 0)),
        left=math.max(0,left-(ending==2 and backoff or 0)),
        cap=ending,
        cap_angle=fraction*360,
    }
end

return M
