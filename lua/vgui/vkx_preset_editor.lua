local PANEL = {}

AccessorFunc( PANEL, "category", "Category", FORCE_STRING )
AccessorFunc( PANEL, "preset", "Preset", FORCE_STRING )

function PANEL:Init()
    self:SetTitle( "VKXTools - Preset Editor" )
    self:SetSizable( true )
    self:SetSize( ScrW() * .4, ScrH() * .4 )
    self:Center()
    self:MakePopup()

    --  left
    self.listview = self:Add( "DListView" )
    self.listview:Dock( LEFT )
    self.listview:DockMargin( 0, 0, 5, 0 )
    self.listview:SetMultiSelect( false )
    self.listview_column = self.listview:AddColumn( "Preset" )
    function self.listview.OnRowSelected( listview, id, row )
        self:SetPreset( row:GetValue( 1 ) )
    end

    self.add_container = self.listview:Add( "DPanel" )
    self.add_container:Dock( BOTTOM )
    self.add_container:DockPadding( 3, 3, 3, 3 )
    self.add_container:SetPaintBackground( false )

    self.new_name_entry = self.add_container:Add( "DTextEntry" )
    self.new_name_entry:Dock( FILL )
    self.new_name_entry:DockMargin( 0, 0, 3, 0 )
    self.new_name_entry:SetPlaceholderText( "New Preset's name" )
    
    self.add_button = self.add_container:Add( "DImageButton" )
    self.add_button:Dock( RIGHT )
    self.add_button:SetImage( "icon16/add.png" )
    self.add_button:SetWide( 18 )
    function self.add_button.Think( button )
        button:SetDisabled( not self.template or #self.new_name_entry:GetValue() <= 0 )
    end
    function self.add_button.DoClick( button )
        local name = self.new_name_entry:GetValue()
        --[[ if name == "Default" then
            Derma_Message( "The name 'Default' is forbidden as it's generated automatically by this system.", "Unable to Save", "OK :("  )
            return
        end ]]

        vkx_presets.set_preset( self.category, name, self.template:get_default_data() )
        self.new_name_entry:SetValue( "" )
    end
    self.new_name_entry:OnChange()
    
    --  right
    self.properties_container = self:Add( "DPanel" )
    self.properties_container:Dock( FILL )
    self.properties_container:DockPadding( 5, 5, 5, 5 )

    self.properties = self.properties_container:Add( "DProperties" )
    self.properties:Dock( FILL )

    --  preset manager
    self.preset_manager = self.properties_container:Add( "DPanel" )
    self.preset_manager:Dock( BOTTOM )
    self.preset_manager:SetPaintBackground( false )

    self.name_entry = self.preset_manager:Add( "DTextEntry" )
    self.name_entry:Dock( FILL )

    self.buttons_container = self.preset_manager:Add( "DPanel" )
    self.buttons_container:Dock( RIGHT )
    self.buttons_container:DockMargin( 5, 0, 0, 0 )
    self.buttons_container:DockPadding( 3, 3, 3, 3 )
    self.buttons_container:SetPaintBackground( false )

    self.save_button = self.buttons_container:Add( "DImageButton" )
    self.save_button:Dock( LEFT )
    self.save_button:SetImage( "icon16/disk.png" )
    self.save_button:SetWide( 16 )
    function self.save_button.DoClick( button )
        local name = self.name_entry:GetValue()
        --[[ if name == "Default" then
            Derma_Message( "The name 'Default' is reserved by this system.", "Unable to Save", "OK :("  )
            return
        end ]]

        --  overriding preset
        if name == self.preset.name then
            local n_diff = table.Count( self:GetPresetDelta() )
            if n_diff == 0 then
                return Derma_Message( "No differences found, can't override the preset..", "Save Preset", "OK" )
            end

            Derma_Query( ( "Are you sure to override the preset '%s' with %d differences?" ):format( name, n_diff ), "Save Preset", 
                "Yes",
                function()
                    vkx_presets.set_preset( self.category, name, self:GetPresetData() )
                end,
                "No",
                function() end
            )
        -- duplicate preset
        else
            Derma_Query( ( "Are you sure to duplicate this preset under the name of '%s'?" ):format( name ), "Save Preset", 
                "Yes",
                function()
                    vkx_presets.set_preset( self.category, name, self:GetPresetData() )
                end,
                "No",
                function() end
            )
        end
    end

    self.delete_button = self.buttons_container:Add( "DImageButton" )
    self.delete_button:Dock( LEFT )
    self.delete_button:DockMargin( 5, 0, 0, 0 )
    self.delete_button:SetImage( "icon16/bin.png" )
    self.delete_button:SetWide( 16 )
    function self.delete_button.DoClick( button )
        if not vkx_presets.get_preset( self.preset.category, self.preset.name ) then return end

        Derma_Query( ( "Are you sure to delete the preset '%s'?" ):format( self.preset.name ), "Delete Preset", 
            "Yes",
            function()
                vkx_presets.remove_preset( self.preset.category, self.preset.name )
                self.properties:Clear()
                self.name_entry:SetValue( "" )
            end,
            "No",
            function() end
        )
    end
    
    vkx_presets.controls[self] = true
end

function PANEL:PerformLayout( w, h )
    baseclass.Get( "DFrame" ).PerformLayout( self, w, h )

    if not self.listview or not self.buttons_container then return end

    self.listview:SetWide( w * .4 )
    self.buttons_container:SetWide( ( #self.buttons_container:GetChildren() + 1 ) * 16 - 5 )
end

function PANEL:SetPreset( name )
    local preset = vkx_presets.get_preset( self.category, name )
    if not preset or not preset.data then return vkx_presets.message( vkx_presets.error_color, "No data found for preset '%s' of '%s'", name, self.category ) end
    if not self.template then return vkx_presets.message( vkx_presets.error_color, "No template found for category '%s'", self.category ) end

    self.preset = preset
    self.properties:Clear()

    self.preset_delta = {}

    for k, v in SortedPairs( preset.data ) do
        local keyvalue = self.template:get( k )
        local row_type = keyvalue:get_type()
        local options = keyvalue:get_options()
        if row_type then
            local row = self.properties:CreateRow( name, k )

            --  setup float decimals
            if row_type == "Float" and options and options.decimals then
                row:Setup( row_type )
                function row.Inner:GetDecimals() 
                    return options.decimals
                end
            end

            row:Setup( row_type, options )

            --  to number
            if row_type == "Float" or row_type == "Int" then 
                row:SetValue( tonumber( v ) )
            else
                row:SetValue( v )
            end

            --  handle changes
            function row.DataChanged( row, value )
                if row_type == "Boolean" then
                    value = tobool( value )
                end

                --  revert to default
                if value == v then 
                    self.preset_delta[k] = nil
                    return 
                end

                --  set value
                self.preset_delta[k] = value
            end
        --  edit table as json
        elseif type( v ) == "table" then
            local json = util.TableToJSON( v )

            local row = self.properties:CreateRow( name, k )
            row:Setup( "Generic" )
            row:SetValue( json )

            local textentry = row.Inner:GetChildren()[1] 
            local default_highlight_color = textentry:GetHighlightColor()
            textentry:SetDrawLanguageID( false )

            function row.DataChanged( row, value )
                local tbl = util.JSONToTable( value )
                if not tbl then 
                    textentry:SetHighlightColor( vkx_presets.error_color )
                    return
                end
                textentry:SetHighlightColor( default_highlight_color )

                --  revert to default
                if value == json then 
                    self.preset_delta[k] = nil
                    return 
                end

                --  set value
                self.preset_delta[k] = tbl
            end
        end
    end

    self.name_entry:SetValue( name )
end

function PANEL:SetCategory( category )
    self.category = category
    self.template = vkx_presets.get_template( category )
    self.listview:Clear()
    self.listview_column:SetName( category )

    for name in pairs( vkx_presets.get_category( category ) ) do
        self.listview:AddLine( name )
    end
end

function PANEL:GetPresetData()
    local data = {}

    for k, v in pairs( self.preset.data ) do
        if not ( self.preset_delta[k] == nil ) then
            data[k] = self.preset_delta[k]
        else
            data[k] = v
        end
    end

    return data
end

function PANEL:GetPresetDelta()
    return self.preset_delta
end

concommand.Add( "vkx_preset_editor", function( ply, cmd, args )
    if not args[1] then return print( "No category is specified!" ) end
    if not vkx_presets.templates[args[1]] then return print( "This preset category doesn't exists!" ) end

    local editor = vgui.Create( "VKXPresetEditor" )
    editor:SetCategory( args[1] )
end, function( cmd, arg )
    local tbl = {}
    
    for k, v in pairs( vkx_presets.templates ) do
        if k:StartWith( arg:Trim() ) then
            tbl[#tbl + 1] = "vkx_preset_editor " .. k
        end
    end

    return tbl
end )

vgui.Register( "VKXPresetEditor", PANEL, "DFrame" )