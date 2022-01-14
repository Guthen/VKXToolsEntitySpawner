local PANEL = {}

AccessorFunc( PANEL, "category", "Category", FORCE_STRING )
AccessorFunc( PANEL, "preset", "Preset", FORCE_STRING )

function PANEL:Init()
    self:SetTall( 22 )
    self:DockMargin( 10, 10, 10, 5 )

    self.combobox = self:Add( "DComboBox" )
    self.combobox:Dock( FILL )
    function self.combobox.OnSelect( combobox, index, value )
        self:SetPreset( value )
    end

    self.buttons_container = self:Add( "DPanel" )
    self.buttons_container:Dock( RIGHT )
    self.buttons_container:DockPadding( 3, 3, 3, 3 )
    self.buttons_container:SetPaintBackground( false )

    self.add_button = self.buttons_container:Add( "DImageButton" )
    self.add_button:Dock( LEFT )
    self.add_button:SetImage( "icon16/disk.png" )
    self.add_button:SetWide( 16 )
    self.add_button:SetTooltip( "Save the current values to a preset" )
    function self.add_button.DoClick()
        if not self.category then return end

        self:AddPreset()
    end
    
    self.edit_button = self.buttons_container:Add( "DImageButton" )
    self.edit_button:Dock( LEFT )
    self.edit_button:DockMargin( 5, 0, 0, 0 )
    self.edit_button:SetImage( "icon16/cog.png" )
    self.edit_button:SetWide( 16 )
    self.edit_button:SetTooltip( "Open the preset editor" )
    function self.edit_button.DoClick()
        if IsValid( self.editor ) then
            self.editor:Remove()
        end

        self.editor = vgui.Create( "VKXPresetEditor" )
        self.editor:SetCategory( self.category )
    end

    self.default_button = self.buttons_container:Add( "DImageButton" )
    self.default_button:Dock( LEFT )
    self.default_button:DockMargin( 5, 0, 0, 0 )
    self.default_button:SetImage( "icon16/arrow_refresh.png" )
    self.default_button:SetWide( 16 )
    self.default_button:SetTooltip( "Reset all values to default" )
    function self.default_button.DoClick()
        if not self.category then return end
        if not self.template or not self.template.default_preset then return end

        self:LoadPreset( self.template.default_preset )
    end

    self.category = ""
    self.callbacks = {}

    vkx_presets.controls[self] = true
end

function PANEL:PerformLayout( w, h )
    self.buttons_container:SetWide( ( #self.buttons_container:GetChildren() + 1 ) * 16 - 5 )
end

function PANEL:SetPreset( name )
    local preset = vkx_presets.get_preset( self.category, name )
    if not preset or not preset.data then return vkx_presets.message( vkx_presets.error_color, "No data found for preset '%s'", name ) end

    self:LoadPreset( preset )
    self.preset = name
end

function PANEL:SetCategory( category )
    self.category = category
    self.template = vkx_presets.get_template( category )
    self.combobox:Clear()

    for name in pairs( vkx_presets.get_category( category ) or {} ) do
        self.combobox:AddChoice( name )
    end

    --self.combobox:AddChoice( "Default", nil, nil, "icon16/cog.png" )
end

function PANEL:AddPreset()
    Derma_StringRequest( "Save Preset", "What is the name for this preset?", self.preset or "My Cool Preset", function( name )
        --[[ if name == "Default" then
            Derma_Message( "The name 'Default' is forbidden as it's generated automatically by this system.", "Unable to Save", "OK :(" )
            return
        end ]]

        local function apply()
            vkx_presets.set_preset( self.category, name, self:BuildPresetData() )
            self.combobox:SetValue( name )
        end

        --  confirmation
        if vkx_presets.get_preset( self.category, name ) then
            Derma_Query( ( "The preset '%s' already exists. Are you sure to override it?" ):format( name ), "Override Preset?", 
                "Yes", apply,
                "No", function()
                    self:AddPreset()
                end 
            )
        else
            apply()
        end
    end )
end

function PANEL:RegisterControl( key, control, name )
    self:RegisterCallback( key, 
        function( value ) 
            control["Set" .. name]( control, value ) 
        end,
        function() 
            return control["Get" .. name]( control ) 
        end
    )
end

local method_by_type = {
    String = "String",
    Int = "Int",
    Float = "Float",
    Boolean = "Bool",
}
function PANEL:RegisterConVar( key, convar_name )
    local convar = GetConVar( convar_name )
    if not convar then 
        return vkx_presets.message( vkx_presets.error_color, "Can't register preset builder for '%s': convar '%s' don't exists", key, convar_name )
    end

    local type_method = method_by_type[self.template:get( key ):get_type()] or "String"
    self:RegisterCallback( key,
        function( value ) 
            local method = convar["Set" .. type_method]
            if not method then 
                return vkx_presets.message( vkx_presets.error_color, "Can't import %s value for %s: method not found", type( value ), key ) 
            end
            
            method( convar, value )
        end,
        function()
            local method = convar["Get" .. type_method]
            if not method then 
                return vkx_presets.message( vkx_presets.error_color, "Can't export %s value for %s: method not found", type( value ), key ) 
            end

            return method( convar )
        end
    )
end

function PANEL:RegisterCallback( key, import_callback, export_callback )
    if not self.template then return vkx_presets.message( vkx_presets.error_color, "No template found, can't register callbacks!" ) end

    self.callbacks[#self.callbacks + 1] = {
        key = key,
        import_callback = import_callback,
        export_callback = export_callback,
    }
end


--[[ 
    @function PANEL:BuildPresetData
        | overridable
        | description: Build data for the new preset
        | return: table data
]]
function PANEL:BuildPresetData()
    local data = {}
    
    for i, v in ipairs( self.callbacks ) do
        if not v.export_callback then
            vkx_presets.message( vkx_presets.error_color, "Can't save preset's value for '%s': export callback not found!", v.key ) 
            continue
        end

        data[v.key] = v.export_callback()
    end

    return data
end

--[[ 
    @function PANEL:LoadPreset
        | overridable
        | description: Load a preset
        | params:
            preset: @Preset
]]
function PANEL:LoadPreset( preset )
    local count = 0

    for i, v in ipairs( self.callbacks ) do
        if preset.data[v.key] == nil then
            vkx_presets.message( vkx_presets.error_color, "Can't load preset's value for '%s': data not found!", v.key )
            continue
        end

        if not v.import_callback then
            vkx_presets.message( vkx_presets.error_color, "Can't load preset's value for '%s': import callback not found!", v.key ) 
            continue
        end
        
        v.import_callback( preset.data[v.key] )
        count = count + 1
    end

    vkx_presets.message( vkx_presets.success_color, "Loaded %d values for preset '%s'", count, preset.name )
end

vgui.Register( "VKXPresetControl", PANEL, "Panel" )