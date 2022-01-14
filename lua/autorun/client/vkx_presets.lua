vkx_presets = vkx_presets or {}
vkx_presets.save_path = "vkx_tools/presets.json"
vkx_presets.error_color = Color( 243, 61, 61 )
vkx_presets.success_color = Color( 64, 243, 148 )
vkx_presets.controls = {} --  list of active controls who have to be refreshed on preset changes
vkx_presets.templates = {} --  list of preset template, used by VKXPresetEditor to handle type of values

function vkx_presets.message( color, text, ... )
    if ... then
        text = text:format( ... )
    end

    MsgC( color, "VKXPresets: " .. text .. "\n" )
end

--[[ 
    @function vkx_presets.load_presets
        | description: Load from file the saved presets
        | return: bool success, string? error_code
]]
function vkx_presets.load_presets()
    vkx_presets.presets = {}

    --  load from file
    local content = file.Read( vkx_presets.save_path, "DATA" )
    if not content then 
        vkx_presets.message( vkx_presets.error_color, "Failed to load presets (ERROR_NO_FILE)" )
        return false, "ERROR_NO_FILE" 
    end

    --  convert back to table
    local data = util.JSONToTable( content )
    if not data then 
        vkx_presets.message( vkx_presets.error_color, "Failed to load presets (ERROR_PARSE_JSON)" )
        return false, "ERROR_PARSE_JSON" 
    end

    --  setup
    for category, presets in pairs( data ) do
        for name, data in pairs( presets ) do
            vkx_presets.new_preset( category, name, data )
        end
    end

    --  count
    local count = 0
    for category, presets in pairs( vkx_presets.presets ) do
        count = count + table.Count( presets )
    end

    vkx_presets.message( vkx_presets.success_color, "Succesfully loaded %d presets", count )
    return true
end

--[[ 
    @function vkx_presets.save_presets
        | description: Save presets to file, will ignore presets with `no_save` set to `true`
        | return: bool success, string? error_code
]]
function vkx_presets.save_presets()
    --  build data to save
    local data, count = {}, 0
    for category, presets in pairs( vkx_presets.presets ) do
        for name, preset in pairs( presets ) do
            if not preset.no_save then
                data[category] = data[category] or {}
                data[category][name] = preset.data
                count = count + 1
            end
        end
    end

    --  ensure directories existence 
    file.CreateDir( string.GetPathFromFilename( vkx_presets.save_path ) )

    local json = util.TableToJSON( data, true )
    if not json then
        vkx_presets.message( vkx_presets.error_color, "Failed to save presets (ERROR_PARSE_TO_JSON)" )
        return false, "ERROR_PARSE_TO_JSON" 
    end

    --  save
    file.Write( vkx_presets.save_path, json )

    vkx_presets.message( vkx_presets.success_color, "Succesfully saved %d presets", count )
    return true
end

--[[ 
    @function vkx_presets.get_category
        | description: Return the presets list in the category
        | params:
            category: string Category to look at
        | return: table[string] presets 
]]
function vkx_presets.get_category( category )
    return vkx_presets.presets[category]
end

--[[ 
    @structure Preset
        | description: Represent a preset
        | params:
            name: string
            category: string
            data: table
            no_save: bool?
    
    @function vkx_presets.new_preset
        | description: Create and register a new preset
        | params:
            category: string
            name: string
            data: table
            no_save: bool?
        | return: @Preset preset
]]
function vkx_presets.new_preset( category, name, data, no_save, is_register )
    local preset = {
        category = category,
        name = name,
        data = data,
        no_save = no_save or nil,
    }

    if not ( is_register == false ) then
        vkx_presets.presets[category] = vkx_presets.presets[category] or {}
        vkx_presets.presets[category][name] = preset
    end
    return preset
end

--[[ 
    @function vkx_presets.set_preset
        | description: Set a preset's value
        | params:
            category: string Category of the preset, most likely addon's name
            name: string Name of the preset
            data: table Data of the preset
            no_save: bool? Save the preset to file
        | return: @Preset preset
]]
function vkx_presets.set_preset( category, name, data, no_save )
    --  register preset
    local old_preset = vkx_presets.get_preset( category, name )
    local preset = vkx_presets.new_preset( category, name, data, no_save )

    --  save to file
    if not no_save then
        vkx_presets.save_presets()
    end

    hook.Run( "vkx_presets:set", old_preset, preset )
    return preset
end

--[[ 
    @function vkx_presets.get_preset
        | description: Get preset from the cache list
        | params:
            category: string Category of the preset
            name: string Name of the preset
        | return: @Preset preset
]]
function vkx_presets.get_preset( category, name )
    if vkx_presets.presets[category] and vkx_presets.presets[category][name] then
        return vkx_presets.presets[category][name]
    end
end

--[[ 
    @function vkx_presets.remove_preset
        | description: Remove a preset
        | params:
            category: string Category of the preset, most likely addon's name
            name: string Name of the preset
]]
function vkx_presets.remove_preset( category, name )
    local preset = vkx_presets.presets[category] and vkx_presets.presets[category][name]
    if preset then
        vkx_presets.presets[category][name] = nil
        if not preset.no_save then
            vkx_presets.save_presets()
        end

        hook.Run( "vkx_presets:remove", preset )
    end
end

--  templates
local Template, KeyValueTemplate = {}, {}

--[[ 
    @class Template
        | description: Represent a preset's category template, containing all key-values and its default values, used by VKXPresetEditor and by VKXPresetControl 
        | params:
            category: string Preset's category
            keyvalues: table[@KeyValueTemplate] All registered keyvalues 
            default_preset: @Preset Default Preset used by VKXPresetControl, built by calling Template:build_default_preset
        | methods:
            @Template Template:init( category )
            @KeyValueTemplate Template:add( key, default )
            @KeyValueTemplate Template:get( string key )
            table[any] Template:get_default_data()

    @function Template:init
        | description: Constructor
        | params:
            category: string Preset's category
        | return @Template self
]]
function Template:init( category )
    self.category = category
    self.keyvalues = {} 
    return self
end

--[[
    @function Template:add
        | description: Add a new keyvalue to the template
        | params:
            key: string
            default: string Default value as text
        | return @KeyValueTemplate keyvalue
]]
function Template:add( key, default )
    self.keyvalues[key] = KeyValueTemplate.init( setmetatable( {}, { __index = KeyValueTemplate } ), default )
    return self.keyvalues[key]
end

--[[
    @function Template:get
        | description: Get specified keyvalue
        | params:
            key: string
        | return @KeyValueTemplate keyvalue
]]
function Template:get( key )
    return self.keyvalues[key]
end

--[[
    @function Template:get_default_data
        | description: Build and get a default data, usable as a preset's data
        | return table data
]]
function Template:get_default_data()
    local data = {}

    for k, v in pairs( self.keyvalues ) do
        data[k] = v:get_value()
    end

    return data
end

--[[
    @function Template:build_default_preset
        | description: Build a default preset using @Template:get_default_data
]]
function Template:build_default_preset()
    self.default_preset = vkx_presets.new_preset( self.category, "Default", self:get_default_data(), true, false )
end

--[[ 
    @class KeyValueTemplate
        | description: Represent a template keyvalue
        | methods:
            @KeyValueTemplate KeyValueTemplate:init( any default )
            any KeyValueTemplate:get_value()
            string KeyValueTemplate:get_type()
            table KeyValueTemplate:get_options()
            @Template KeyValueTemplate:as( string control_type, table options )

    @function KeyValueTemplate:init
        | description: Constructor
        | params:
            default: string Default value as text
        | return @KeyValueTemplate self
]]
function KeyValueTemplate:init( default )
    self.default = default
    return self
end

local convertion_types = {
    ["Int"] = tonumber,
    ["Float"] = tonumber,
    ["Boolean"] = tobool,
}
--[[ 
    @function KeyValueTemplate:get_value
        | description: Get the default value, might be converted if a control type is set
        | return any value
]]
function KeyValueTemplate:get_value()
    local type = self:get_type()
    if convertion_types[type] then return convertion_types[type]( self.default ) end
    return self.default
end

--[[ 
    @function KeyValueTemplate:get_type
        | description: Get registered type if exists
        | return string control_type
]]
function KeyValueTemplate:get_type()
    return self.control and self.control.type
end

--[[ 
    @function KeyValueTemplate:get_options
        | description: Get registered options if exists
        | return table options
]]
function KeyValueTemplate:get_options()
    return self.control and self.control.options
end

--[[ 
    @function KeyValueTemplate:as
        | description: Register keyvalue's type and options
        | params:
            control_type: string Type from DProperties's types (e.g.: 'Int', 'Float', 'Boolean', etc.)
            options: table Options from DProperties's type vars
        | return @KeyValueTemplate self
]]
function KeyValueTemplate:as( control_type, options )
    self.control = {
        type = control_type,
        options = options,
    }
    return self
end


--[[ 
    @function vkx_presets.new_template
        | description: Create and register a new template
        | params:
            category: string Preset's category to register
        | return @Template template
]]
function vkx_presets.new_template( category )
    vkx_presets.templates[category] = Template.init( setmetatable( {}, { __index = Template } ), category )
    return vkx_presets.templates[category]
end

--[[ 
    @function vkx_presets.get_template
        | description: Get a registered template
        | params:
            category: string Preset's category to retrieve
        | return @Template template
]]
function vkx_presets.get_template( category )
    return vkx_presets.templates[category]
end

--  refresh controls
function vkx_presets.refresh_controls()
    for control in pairs( vkx_presets.controls ) do
        if not IsValid( control ) then
            vkx_presets.controls[control] = nil
            continue
        end

        control:SetCategory( control.category )
    end
end
hook.Add( "vkx_presets:set", "vkx_presets:refresh_control", vkx_presets.refresh_controls )
hook.Add( "vkx_presets:remove", "vkx_presets:refresh_control", vkx_presets.refresh_controls )

vkx_presets.load_presets()