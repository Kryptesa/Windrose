-- Contract/lifecycle checks for the shipping adapter; this is not an engine emulator.
require('config').visual_test_mode=false
local next_address = 10
local created, removed, source = {}, 0, nil
local hooks, keys, timer = {}, {}, nil
local fail_attach = false
local on_new_widget,notifications_registered=nil,0
function NotifyOnNewObject(path,callback)
    assert(path=='/Game/UI/HUD/CharacterPanel/StaminaRing/WBP_StaminaRing.WBP_StaminaRing_C')
    notifications_registered=notifications_registered+1;on_new_widget=callback
end
local function object(o)
    next_address=next_address+1
    o=o or {};o.address=next_address;o.alive=true
    function o:IsValid() return self.alive end
    function o:GetAddress() assert(self.alive);return self.address end
    return o
end
local function clone(value)
    if type(value)~='table' then return value end
    local out={};for k,v in pairs(value) do out[k]=clone(v) end;return out
end
local function slot()
    local o=object({LayoutData={Offsets={Left=10,Top=20,Right=64,Bottom=64},
        Anchors={Minimum={X=0,Y=0},Maximum={X=0,Y=0}},Alignment={X=0.5,Y=0.5}},ZOrder=2})
    function o:GetSize() return {X=self.LayoutData.Offsets.Right,Y=self.LayoutData.Offsets.Bottom} end
    function o:SetLayout(v) assert(type(v.Offsets.Right)=='number');self.LayoutData=clone(v) end
    function o:SetZOrder(v) self.ZOrder=v end
    function o:SetAnchors(v) assert(type(v.Minimum.X)=='number');self.LayoutData.Anchors=clone(v) end
    function o:SetAlignment(v) assert(type(v.X)=='number' and type(v.Y)=='number');self.LayoutData.Alignment=clone(v) end
    function o:SetPosition(v)
        assert(type(v.X)=='number' and type(v.Y)=='number');self.position=clone(v)
        self.LayoutData.Offsets.Left,self.LayoutData.Offsets.Top=v.X,v.Y
    end
    function o:SetSize(v)
        assert(v.X>0 and v.Y>0);self.size=clone(v)
        self.LayoutData.Offsets.Right,self.LayoutData.Offsets.Bottom=v.X,v.Y
    end
    return o
end
local function image()
    local o=object({ColorAndOpacity={R=1,G=0.8,B=0.1,A=1},RenderOpacity=0.75,
                    RenderTransform={Scale={X=1,Y=1}},RenderTransformPivot={X=0.5,Y=0.5},Slot=slot()})
    function o:SetBrushFromTexture(t,match) assert(t.texture and match==false);self.texture=t end
    function o:SetColorAndOpacity(v) assert(type(v.R)=='number' and type(v.A)=='number');self.ColorAndOpacity=v end
    function o:SetVisibility(v) self.visibility=v end
    function o:GetVisibility() return self.visibility or 0 end
    function o:SetRenderTransformPivot(v) assert(type(v.X)=='number' and type(v.Y)=='number');self.RenderTransformPivot=clone(v) end
    function o:SetClipping(v) assert(v==1);self.clipping=v end
    function o:SetRenderTransformAngle(v) assert(type(v)=='number');self.angle=v end
    function o:SetRenderScale(v) self.renderScale={X=v.X,Y=v.Y} end
    function o:SetRenderOpacity(v) assert(v>=0 and v<=1);self.RenderOpacity=v end
    function o:GetRenderOpacity() return self.RenderOpacity end
    function o:GetParent() return self.parent end
    return o
end
local function canvas()
    local o=image();o.children={}
    function o:IsA(path) assert(type(path)=='string');return path=='/Script/UMG.CanvasPanel' end
    function o:AddChildToCanvas(child)
        if fail_attach then error('simulated attachment failure') end
        self.children[#self.children+1]=child;child.parent=self;child.Slot=slot();return child.Slot
    end
    function o:SetRenderTransform(v) assert(v.Scale.X==1);self.RenderTransform=v end
    function o:RemoveFromParent() self.detached=true;self.parent=nil;removed=removed+1 end
    return o
end
function FName(s) return {fname=s} end
function StaticFindObject(path)
    local o=object({class=path})
    if path=='/Script/Engine.Default__KismetRenderingLibrary' then
        function o:ImportFileAsTexture2D(widget,filename)
            assert(widget.WidgetTree and filename:match('ring%-%d+%-%a+%.png$'))
            return object({texture=true,filename=filename})
        end
    end
    return o
end
function StaticConstructObject(class,tree,name)
    assert(tree.tree and name.fname)
    local o=class.class=='/Script/UMG.CanvasPanel' and canvas() or image()
    created[#created+1]=o;return o
end
function LoadAsset(path) assert(path:find('WhiteSquareTexture'));return object({texture=true}),true,true end
function ExecuteInGameThread(fn) fn() end
function LoopAsync(interval,fn) assert(interval==1000);timer=fn end
function RegisterHook(path,fn) hooks[path]=fn;return 1,2 end
function RegisterKeyBind(key,fn) keys[key]=fn end
package.preload['diagnostics']=function() return {inspect_now=function() end} end
local base='/Game/UI/HUD/CharacterPanel/StaminaRing/WBP_StaminaRing.WBP_StaminaRing_C'
local tree=object({tree=true})
local original=image();original.parent=canvas();source=original
local model=object({current=220,maximum=240})
function model:GetCurrentStamina() return self.current end
function model:GetMaxStamina() return self.maximum end
local widget=object({WidgetTree=tree,img_StaminaBar=original,Model=model})
function widget:IsInViewport() return self.in_viewport~=false end
local permanent_override,source_failure=nil,false
package.preload['source_reader']=function() return {read=function(_,maximum)
    if source_failure then error('simulated source mismatch') end
    local permanent=permanent_override or maximum
    return {verified=true,maximum=maximum,permanent_maximum=permanent,temporary_maximum=maximum-permanent,
        permanent_endurance=4,temporary_endurance=0,temporary_direct_stamina=maximum-permanent,effects={}}
end} end
function widget:GetFullName() return 'WBP_StaminaRing_C LiveRing' end
function FindAllOf(name) assert(name=='WBP_StaminaRing_C');return {widget} end
local context={get=function() return widget end}
local delta={get=function() return 1/60 end}

local app=require('app')
local clock=0
local function tick() clock=clock+1/60;app.frame(1/60,clock) end
tick(context,{},delta)
assert(original.ColorAndOpacity.A==0,'original paint must hide after successful replacement')
assert(original.RenderOpacity==0.75,'game animation opacity must remain untouched')
if layout_case then
    local first_root=created[1]
    local before=#created
    if layout_case=='late_position' then
        original.Slot:SetPosition({X=960,Y=540})
        original.Slot:SetAnchors({Minimum={X=0.5,Y=0.5},Maximum={X=0.5,Y=0.5}})
        original.Slot:SetAlignment({X=0.25,Y=0.75})
        original:SetRenderTransformPivot({X=0.2,Y=0.3})
        original.Slot:SetZOrder(7)
        tick()
        local layout=first_root.Slot.LayoutData
        assert(layout.Offsets.Left==960 and layout.Offsets.Top==540,
            'replacement stayed at its construction coordinates after native positioning')
        assert(layout.Anchors.Minimum.X==0.5 and layout.Anchors.Maximum.Y==0.5)
        assert(layout.Alignment.X==0.25 and layout.Alignment.Y==0.75)
        assert(first_root.RenderTransformPivot.X==0.2 and first_root.RenderTransformPivot.Y==0.3)
        assert(first_root.Slot.ZOrder==8)
        original.Slot:SetPosition({X=400,Y=300});tick()
        assert(first_root.Slot.LayoutData.Offsets.Left==400,'world-projected movement must keep tracking')
        assert(#created==before,'following layout must not reconstruct the ring widgets')
    elseif layout_case=='late_size' then
        original.Slot:SetSize({X=96,Y=80});tick()
        local root
        for _,o in ipairs(created) do if o.parent==original.parent and not o.detached then root=o end end
        assert(root and root~=first_root,'late source size must rebuild the baked local center')
        assert(root.Slot.LayoutData.Offsets.Right==96 and root.Slot.LayoutData.Offsets.Bottom==80)
    else error('unknown layout fixture') end
    app.stop();return
end
if lifecycle_case then
    if lifecycle_case=='new_widget' or lifecycle_case=='new_widget_immediate' or lifecycle_case=='new_widget_delayed_size' then
        widget.in_viewport=false -- Unreal may retain the previous HUD until GC.
        original=image();original.parent=canvas()
        widget=object({WidgetTree=tree,img_StaminaBar=original,Model=model})
        function widget:GetFullName() return 'WBP_StaminaRing_C ReplacementRing' end
        function widget:IsInViewport() return true end
        if lifecycle_case=='new_widget_delayed_size' then
            original.Slot.LayoutData.Offsets.Right,original.Slot.LayoutData.Offsets.Bottom=0,0
            on_new_widget(widget);tick()
            assert(original.ColorAndOpacity.A==1,'zero-size source must not be hidden prematurely')
            original.Slot:SetSize({X=64,Y=64})
        elseif lifecycle_case=='new_widget_immediate' and on_new_widget then on_new_widget(widget) end
    elseif lifecycle_case=='new_image' then
        original=image();original.parent=canvas();widget.img_StaminaBar=original
    elseif lifecycle_case=='paint_reset' then
        original.ColorAndOpacity={R=1,G=0.8,B=0.1,A=1}
    elseif lifecycle_case=='new_parent' then
        original.parent=canvas()
    elseif lifecycle_case=='detached_panel' then
        created[1]:RemoveFromParent()
        original.ColorAndOpacity.A=1
    elseif lifecycle_case=='pending_widget' then
        widget.img_StaminaBar=nil
        clock=clock+1.2;tick()
        original=image();original.parent=canvas();widget.img_StaminaBar=original
    else error('unknown lifecycle fixture') end
    if lifecycle_case~='new_widget_immediate' and lifecycle_case~='new_widget_delayed_size' then clock=clock+1.2 end
    tick()
    assert(original.ColorAndOpacity.A==0,
        'stock ring remained visible after menu lifecycle event: '..lifecycle_case)
    app.stop()
    assert(original.ColorAndOpacity.A==1,'replacement lifecycle must preserve stock restoration')
    return
end
assert(created[1].renderScale.X==1 and created[1].renderScale.Y==1,
       'stroke refinement must preserve the original overall HUD scale')
local before=#created
model.current=120
for i=1,20 do tick(context,{},delta) end
assert(#created==before,'per-frame updates must not allocate new widgets')
assert(model.current==120 and model.maximum==240,'adapter must never write gameplay values')
model.current=30 -- 12.5%: warm even above the fully-orange/critical threshold.
tick()
local warmed
for _,o in ipairs(created) do
    local layer=o.texture and o.texture.filename:match('ring%-%d+%-(%a+)%.png$')
    if layer=='fill' or layer=='paint' or layer=='hatch' then
        local r=o.ColorAndOpacity.R
        assert(r>0.188 and r<0.68,'first warning frame must have an intermediate tint')
        warmed={image=o,red=r}
        if layer~='fill' then
            assert(o.angle==-o.parent.angle,'fill texture must not rotate with the clipping stencil')
        end
    end
end
assert(warmed,'foreground tint must update on the native image')
model.current=120;tick()
assert(warmed.image.ColorAndOpacity.R<warmed.red and warmed.image.ColorAndOpacity.R>0.188,
       'regeneration must ease back toward green instead of snapping')
model.current=0.1
for i=1,120 do tick() end
local visible_cap=false
for _,o in ipairs(created) do
    local layer=o.texture and o.texture.filename:match('ring%-%d+%-(%a+)%.png$')
    if (layer=='fillcap' or layer=='paintcap' or layer=='hatchcap') and o.RenderOpacity>0 then
        local p=o.parent;local visible=true
        while p do
            if p.RenderOpacity==0 then visible=false end
            p=p.parent
        end
        if visible then visible_cap=true end
    end
end
assert(visible_cap,'very small stamina values must retain their soft cap when the hard body is empty')
app.toggle()
assert(original.ColorAndOpacity.A==1,'disable restores source tint')
local n=#created;tick(context,{},delta);assert(#created==n,'disabled mod must not rebuild')
app.toggle();tick(context,{},delta)
assert(notifications_registered==1,'toggle/reload must not register duplicate construction notifications')
model.maximum=180;model.current=180;tick(context,{},delta)
assert(removed>=2,'max capacity changes must detach previous rings')
app.stop()
assert(original.ColorAndOpacity.A==1,'widget destruction restores original')

-- A food/equipment swap can change source ownership without changing total max.
permanent_override=150
clock=clock+1;tick()
local before_swap=#created
permanent_override=160
clock=clock+1;tick()
assert(#created>before_swap,'same-total source changes must rebuild the two groups')
source_failure=true
clock=clock+1;tick()
assert(original.ColorAndOpacity.A==1,'unverified split must restore the original indicator')
source_failure=false
clock=clock+1;tick()
assert(original.ColorAndOpacity.A==0,'a complete native snapshot must recover without restarting')
app.stop()

-- A native construction failure must remove partial UI and preserve original.
fail_attach=true
clock=clock+2
assert(not pcall(tick),'simulated native failure must reach the scheduler error handler')
app.stop()
assert(original.ColorAndOpacity.A==1,'failed creation must leave original visible')
assert(created[#created].detached,'failed replacement must detach partial canvas')
print('Adapter contract and lifecycle checks passed')
