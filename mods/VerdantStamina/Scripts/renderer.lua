local Core=require("core")
local M={}
M.revision="zelda-mask-v13-textured-fill"
local serial=0
local generation=tostring(math.floor(os.clock()*1000))
local source=debug.getinfo(1,"S").source:gsub("^@","")
local directory=source:match("^(.*[\\/])") or ""
local assets=directory.."../Assets/"
local textures={}
local function valid(o) return o and o:IsValid() end
local function vec(x,y) return {X=x,Y=y} end
local function copy_color(o) return {R=o.R,G=o.G,B=o.B,A=o.A} end

local function construct(class,tree,label)
    serial=serial+1
    local o=StaticConstructObject(class,tree,FName("VerdantStamina_"..generation.."_"..label.."_"..serial))
    assert(valid(o),"Cannot construct "..label)
    return o
end

local function texture(widget,index,layer)
    local key=index.."-"..layer
    if not valid(textures[key]) then
        local library=StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary")
        assert(valid(library),"KismetRenderingLibrary unavailable")
        textures[key]=library:ImportFileAsTexture2D(widget,assets.."ring-"..key..".png")
        assert(valid(textures[key]),"Cannot import antialiased ring mask: "..key)
    end
    return textures[key]
end

local function set_arc(arc,fraction)
    local edge=Core.arc_edges(fraction,arc.inner_radius,arc.softness)
    for index,part in ipairs({{arc.right,edge.right},{arc.left,edge.left}}) do
        local half,angle=part[1],part[2]
        if half.angle~=angle then
            half.rotating:SetRenderTransformAngle(angle)
            -- The stencil rotates; the grain stays fixed on the HUD surface.
            if arc.textured then half.image:SetRenderTransformAngle(-angle) end
            half.rotating:SetRenderOpacity(angle>0 and 1 or 0)
            half.angle=angle
        end
        local cap_visible=edge.cap==index
        if half.cap_visible~=cap_visible then
            half.cap:SetRenderOpacity(cap_visible and 1 or 0)
            half.cap_visible=cap_visible
        end
        if cap_visible and half.cap_angle~=edge.cap_angle then
            half.cap:SetRenderTransformAngle(edge.cap_angle)
            half.cap_angle=edge.cap_angle
        end
    end
end

function M.create(widget,maximum,config,sources)
    local self={widget=widget,config=config,rings={},maximum=maximum,hidden=false,sources=sources}
    local ok,err=pcall(function()
        local original=widget.img_StaminaBar
        assert(valid(original),"img_StaminaBar unavailable")
        local parent,tree,original_slot=original:GetParent(),widget.WidgetTree,original.Slot
        assert(valid(parent) and valid(tree) and valid(original_slot),"Stamina canvas unavailable")
        assert(parent:IsA("/Script/UMG.CanvasPanel"),"Stamina parent is not CanvasPanel")
        local image_class=StaticFindObject("/Script/UMG.Image")
        local canvas_class=StaticFindObject("/Script/UMG.CanvasPanel")
        assert(valid(image_class) and valid(canvas_class),"UMG classes unavailable")
        self.original,self.original_color=original,copy_color(original.ColorAndOpacity)
        self.panel=construct(canvas_class,tree,"Canvas")
        local root_slot=parent:AddChildToCanvas(self.panel)
        assert(valid(root_slot),"Cannot attach stamina canvas")
        root_slot:SetLayout(original_slot.LayoutData)
        root_slot:SetZOrder(original_slot.ZOrder+1)
        self.panel:SetVisibility(3)
        self.panel:SetRenderTransformPivot(original.RenderTransformPivot)
        local size=original_slot:GetSize()
        self.source_size={X=size.X,Y=size.Y}
        local cx,cy=size.X/2,size.Y/2

        local function attach(parent_node,class,label,x,y,w,h,pivot_x,pivot_y,clip)
            local o=construct(class,tree,label)
            local slot=parent_node:AddChildToCanvas(o)
            assert(valid(slot),"Cannot attach "..label)
            slot:SetAnchors({Minimum=vec(0,0),Maximum=vec(0,0)})
            slot:SetAlignment(vec(0,0))
            slot:SetPosition(vec(x,y));slot:SetSize(vec(w,h))
            o:SetVisibility(3)
            o:SetRenderTransformPivot(vec(pivot_x or 0,pivot_y or 0))
            if clip then o:SetClipping(1) end -- ClipToBounds, intersect rotated stencil clips.
            return o
        end
        local function arc(layout,layer,color)
            local ring,scale=layout.ring,layout.scale
            local radius=(ring.radius+ring.thickness/2+1)*scale -- Transparent AA guard band.
            local cx,cy=cx+layout.x,cy+layout.y
            local image_texture=texture(widget,ring.index,layer)
            local cap_texture=texture(widget,ring.index,layer.."cap")
            local function half(is_right)
                -- A fixed half-plane intersects a rotating opposite half-plane.
                -- The circular texture is rotationally symmetric, so it rotates
                -- with the mask and needs no inverse/counter transform.
                local fixed=attach(self.panel,canvas_class,"Half",is_right and cx or cx-radius,cy-radius,
                                   radius,radius*2,0,0,true)
                local rotating=attach(fixed,canvas_class,"Mask",is_right and -radius or radius,0,
                                      radius,radius*2,is_right and 1 or 0,0.5,true)
                local image=attach(rotating,image_class,"Ring",is_right and 0 or -radius,0,
                                   radius*2,radius*2,0.5,0.5,false)
                image:SetBrushFromTexture(image_texture,false)
                image:SetColorAndOpacity(color)
                local cap=attach(fixed,image_class,"SoftEdge",is_right and -radius or 0,0,
                                 radius*2,radius*2,0.5,0.5,false)
                cap:SetBrushFromTexture(cap_texture,false)
                cap:SetColorAndOpacity(color)
                return {fixed=fixed,rotating=rotating,image=image,cap=cap}
            end
            local result={right=half(true),left=half(false),
                          textured=layer=="paint" or layer=="hatch",
                          inner_radius=(ring.radius-ring.thickness/2)*scale,softness=config.edge_softness*scale}
            set_arc(result,0)
            return result
        end
        for _,layout in ipairs(Core.layout(maximum,config,sources)) do
            local ring=layout.ring
            local background=arc(layout,"track",config.background_color)
            set_arc(background,ring.available/ring.capacity)
            self.rings[#self.rings+1]={ring=ring,kind=layout.kind,background=background,
                foreground=arc(layout,config.surface_style=="flat" and "fill" or config.surface_style,
                    layout.kind=="temporary" and config.temporary_color or config.color)}
        end
    end)
    if not ok then M.destroy(self);error(err) end
    return self
end

function M.available(widget)
    if not valid(widget) or not valid(widget.WidgetTree) then return false end
    local image=widget.img_StaminaBar
    if not valid(image) or not valid(image.Slot) then return false end
    local size=image.Slot:GetSize()
    if size.X<=0 or size.Y<=0 then return false end
    local parent=image:GetParent()
    return valid(parent) and parent:IsA("/Script/UMG.CanvasPanel")
end

function M.matches(self,widget)
    if not valid(self.original) or not valid(self.panel) or not valid(widget.WidgetTree) then return false end
    local image=widget.img_StaminaBar
    if not valid(image) or image:GetAddress()~=self.original:GetAddress() then return false end
    if not valid(image.Slot) then return false end
    local size=image.Slot:GetSize()
    if size.X~=self.source_size.X or size.Y~=self.source_size.Y then return false end
    local parent,attached=image:GetParent(),self.panel:GetParent()
    return valid(parent) and valid(attached) and parent:GetAddress()==attached:GetAddress()
end

function M.update(self,sample)
    assert(valid(self.widget) and valid(self.original) and valid(self.panel),"Stamina widget expired")
    -- World projection/menu initialization updates CanvasPanelSlot after the
    -- object constructor. RenderTransform alone does not contain that position.
    -- Follow the same live anchor/offset/alignment data, not its startup snapshot.
    local source_slot=self.original.Slot
    self.panel.Slot:SetLayout(source_slot.LayoutData)
    self.panel.Slot:SetZOrder(source_slot.ZOrder+1)
    self.panel:SetRenderTransformPivot(self.original.RenderTransformPivot)
    self.panel:SetRenderTransform(self.original.RenderTransform)
    local original_scale=self.original.RenderTransform.Scale
    self.panel:SetRenderScale(vec(original_scale.X*self.config.ui_scale,original_scale.Y*self.config.ui_scale))
    self.panel:SetRenderOpacity(self.original:GetRenderOpacity())
    local visibility=self.original:GetVisibility()
    self.panel:SetVisibility((visibility==0 or visibility==3 or visibility==4) and 3 or visibility)
    local update_color=self.warning==nil or math.abs(self.warning-sample.warning)>0.0001
    local color=update_color and Core.tint(sample,self.config) or nil
    local permanent,temporary=sample.shown,0
    if self.sources then permanent,temporary=require("source_model").partition(sample.shown,self.sources) end
    for _,entry in ipairs(self.rings) do
        set_arc(entry.foreground,Core.fill(entry.ring,entry.kind=="temporary" and temporary or permanent))
        -- Yellow remains a separate source cue; low-stamina warming belongs to green.
        if update_color and entry.kind~="temporary" then
            entry.foreground.right.image:SetColorAndOpacity(color)
            entry.foreground.left.image:SetColorAndOpacity(color)
            entry.foreground.right.cap:SetColorAndOpacity(color)
            entry.foreground.left.cap:SetColorAndOpacity(color)
        end
    end
    if update_color then self.warning=sample.warning end
    if not self.hidden or self.original.ColorAndOpacity.A~=0 then
        -- Construct/reveal/menu transitions can repaint the stock image after
        -- it was hidden once. Preserve the game's latest tint for restoration.
        if self.original.ColorAndOpacity.A~=0 then self.original_color=copy_color(self.original.ColorAndOpacity) end
        local color=copy_color(self.original.ColorAndOpacity);color.A=0
        self.original:SetColorAndOpacity(color);self.hidden=true
    end
end

function M.destroy(self)
    if not self then return end
    if self.hidden and valid(self.original) then pcall(function() self.original:SetColorAndOpacity(self.original_color) end) end
    if valid(self.panel) then pcall(function() self.panel:RemoveFromParent() end) end
    self.hidden=false;self.rings={}
end

return M
