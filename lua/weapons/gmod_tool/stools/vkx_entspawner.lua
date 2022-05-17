TOOL.Category = "VKX Tools"
TOOL.Name = "#tool.vkx_entspawner.name"

TOOL.model = "models/editor/playerstart.mdl"

TOOL.should_refresh_preview = true

local convars = {}
function TOOL:LeftClick( tr )
    if SERVER then return true end
    if not IsFirstTimePredicted() then return end

    if not self.preview_locations or #self.preview_locations == 0 then return false end
    if not vkx_entspawner.ents_chance or table.Count( vkx_entspawner.ents_chance ) == 0 then 
        notification.AddLegacy( "You must have selected entities to spawn!", NOTIFY_ERROR, 3 )
        return true
    end

    local is_spawner = tobool( self:GetClientNumber( "is_spawner", 0 ) )
    net.Start( "vkx_entspawner:spawn" )
        --  locations
        net.WriteUInt( #self.preview_locations, vkx_entspawner.NET_LOCATIONS_BITS )
        for i, v in ipairs( self.preview_locations ) do
            net.WriteVector( v.pos )
            net.WriteAngle( v.ang )
        end
        --  entities chance
        net.WriteUInt( #vkx_entspawner.ents_chance, vkx_entspawner.NET_ENTS_CHANCE_BITS )
        for i, v in ipairs( vkx_entspawner.ents_chance ) do
            net.WriteString( v.key )
            net.WriteFloat( v.percent )
        end
        --  spawner
        net.WriteBool( is_spawner )
        if is_spawner then
            net.WriteBool( self:GetClientNumber( "is_perma", 0 ) )
            net.WriteUInt( self:GetClientNumber( "spawner_max", 1 ), vkx_entspawner.NET_SPAWNER_MAX_ENTITIES_BITS )
            net.WriteUInt( self:GetClientNumber( "spawner_delay", 3 ), vkx_entspawner.NET_SPAWNER_DELAY_BITS )
            net.WriteUInt( self:GetClientNumber( "spawner_radius", 0 ), vkx_entspawner.NET_SPAWNER_RADIUS_BITS )
            net.WriteBool( self:GetClientNumber( "spawner_radius_disappear", 0 ) )
        end
    net.SendToServer()

    return true
end

local min_dist = 32
local min_dist_sqr = min_dist ^ 2
function TOOL:RightClick( tr )
    if CLIENT then return true end
    if not IsFirstTimePredicted() then return end

    for id, spawner in pairs( vkx_entspawner.spawners ) do
        for i, v in ipairs( spawner.locations ) do
            if v.pos:DistToSqr( tr.HitPos ) <= min_dist_sqr then
                vkx_entspawner.delete_spawner( id )
                return true
            end
        end
    end
end

if SERVER then
    util.AddNetworkString( "vkx_entspawner:spawn" )

    local last_times = {}
    net.Receive( "vkx_entspawner:spawn", function( len, ply )
        if not ply:IsSuperAdmin() then return ply:ChatPrint( "This tool is reserved for SuperAdmin only!" ) end
        if last_times[ply] and CurTime() - last_times[ply] <= .1 then return vkx_entspawner.debug_print( "%q is spamming, aborting request", ply:GetName() ) end --  avoid unwanted spam
        
        --  locations
        local locations_count = net.ReadUInt( vkx_entspawner.NET_LOCATIONS_BITS )
        if locations_count == 0 then 
            return vkx_entspawner.debug_print( "failed to receive the length of the locations from %q", ply:GetName() ) 
        end

        local locations = {}
        for i = 1, locations_count do
            local pos = net.ReadVector()
            if pos:IsZero() then return vkx_entspawner.debug_print( "failed to receive a valid location position from %q", ply:GetName() ) end
            
            local ang = net.ReadAngle()
            if ang:IsZero() then return vkx_entspawner.debug_print( "failed to receive a valid location angle from %q", ply:GetName() ) end
            
            locations[i] = {
                pos = pos,
                ang = ang,
            }
        end

        --  chances
        local chances_count = net.ReadUInt( vkx_entspawner.NET_ENTS_CHANCE_BITS )
        if chances_count == 0 then 
            return vkx_entspawner.debug_print( "failed to receive the length of the entities chance from %q", ply:GetName() ) 
        end

        local chances = {}
        for i = 1, chances_count do
            local key = net.ReadString()
            if #key == 0 then return vkx_entspawner.debug_print( "failed to receive a valid entity key from %q", ply:GetName() ) end

            local percent = net.ReadFloat()
            if percent == 0 then return vkx_entspawner.debug_print( "failed to receive a valid entity percent from %q", ply:GetName() ) end

            chances[i] = {
                key = key,
                percent = percent,
            }
        end

        --  spawner
        local is_spawner, is_perma, spawner_max, spawner_delay, spawner_radius, spawner_radius_disappear = net.ReadBool()
        if is_spawner then
            is_perma = net.ReadBool()
            spawner_max = net.ReadUInt( vkx_entspawner.NET_SPAWNER_MAX_ENTITIES_BITS )
            spawner_delay = net.ReadUInt( vkx_entspawner.NET_SPAWNER_DELAY_BITS )
            spawner_radius = net.ReadUInt( vkx_entspawner.NET_SPAWNER_RADIUS_BITS )
            spawner_radius_disappear = net.ReadBool()

            local spawner = vkx_entspawner.new_spawner( {
                locations = locations,
                entities = chances,
                max = spawner_max,
                delay = spawner_delay,
                perma = is_perma,
                radius = spawner_radius,
                radius_disappear = spawner_radius_disappear,
            } )
            if not is_perma then 
                undo.Create( "Entities Spawners" )
                undo.AddFunction( function()
                    vkx_entspawner.delete_spawner( spawner.id )
                end )
                undo.SetPlayer( ply )
                undo.Finish()
            end
        else
            local messages = {}

            --  spawning
            undo.Create( "Entities Groups" )
            vkx_entspawner.run_spawner( {
                locations = locations,
                entities = chances,
                max = 1,
            }, function( obj, type )
                cleanup.Add( ply, type, obj )
                undo.AddEntity( obj )
            end, function( err, obj, blocked_entity )
                if err == "cant_spawn" then
                    local msg = ( "%q is preventing %q from spawning" ):format( blocked_entity:GetClass(), obj:GetClass() )
                    messages[msg] = ( messages[msg] or 0 ) + 1
                end
            end )
            undo.SetPlayer( ply )
            undo.Finish()

            --  notification
            for msg, count in pairs( messages ) do
                vkx_entspawner.notify( ply, msg .. " (x" .. count .. ")", 1 )
            end
        end

        last_times[ply] = CurTime()
    end )
elseif CLIENT then
    --  information
    TOOL.Information = {
        { 
            name = "left",
        },
        {
            name = "right",
        },
        {
            name = "reload",
        },
    }

    --  language
    language.Add( "tool.vkx_entspawner.name", "Entity Spawner" )
    language.Add( "tool.vkx_entspawner.desc", "Create customizable Entity Spawners." )
    language.Add( "tool.vkx_entspawner.left", "Spawn Entities/Spawners" )
    language.Add( "tool.vkx_entspawner.right", "Remove already-placed Spawners" )
    language.Add( "tool.vkx_entspawner.reload", "Copy hovering spawner settings or Re-generate locations otherwise" )

    --  ghost entities
    vkx_entspawner.delete_preview_locations()  --  auto-refresh
    TOOL.preview_locations = {}
    function TOOL:ClearPreviewLocations()
        self.preview_locations = {}
    end

    function TOOL:UpdatePreviewLocations( pos )
        if not self.locations and not self:ComputePreviewLocations() then return end

        local ang = Angle( 0, ( LocalPlayer():GetPos() - pos ):Angle().y, 0 )
        for i, v in ipairs( self.locations ) do
            --  rotate position
            local rotated_pos = Vector( v.pos:Unpack() )
            rotated_pos:Rotate( ang )

            --  compute final position and angle
            self.preview_locations[i] = self.preview_locations[i] or {}
            self.preview_locations[i].pos = pos + rotated_pos
            self.preview_locations[i].ang = ang + v.ang
        end
    end

    function TOOL:ComputePreviewLocations()
        if not vkx_entspawner.is_holding_tool() then return end

        local shapes, shape = list.Get( "vkx_entspawner_shapes" ), self:GetClientInfo( "shape" )
        if not shapes[shape] or not shapes[shape].compute then return false end

        local locations = shapes[shape].compute( self )
        if not locations then return false end

        self.locations = locations
        self:ClearPreviewLocations()
        return true
    end

    function TOOL:Think()
        if #self.preview_locations == 0 then
            self:ComputePreviewLocations()
        end
        self:UpdatePreviewLocations( self:GetOwner():GetEyeTrace().HitPos )
    end

    function TOOL:Reload( tr )
        for id, spawner in pairs( vkx_entspawner.spawners ) do
            for i, loc in ipairs( spawner.locations ) do
                if loc.pos:DistToSqr( tr.HitPos ) <= min_dist_sqr then
                    --  copying values
                    vkx_entspawner.ents_chance = {}
                    for j, ent in ipairs( spawner.entities ) do
                        vkx_entspawner.ents_chance[j] = ent
                    end
                    GetConVar( "vkx_entspawner_is_spawner" ):SetBool( true )
                    GetConVar( "vkx_entspawner_is_perma" ):SetBool( spawner.perma )
                    GetConVar( "vkx_entspawner_spawner_max" ):SetInt( spawner.max )
                    GetConVar( "vkx_entspawner_spawner_delay" ):SetInt( spawner.delay )
                    GetConVar( "vkx_entspawner_spawner_radius" ):SetInt( spawner.radius )
                    GetConVar( "vkx_entspawner_spawner_radius_disappear" ):SetBool( spawner.radius_disappear )
                    self:RebuildCPanel() --  necessary to updates selected entities list 

                    return true
                end
            end
        end

        self:ComputePreviewLocations()
        return true
    end

    --[[ function TOOL:Holster()
        self:ClearPreviewLocations()
    end ]]

    --  draw spawners
    local preview_model = ClientsideModel( TOOL.model )
    preview_model:SetNoDraw( true )

    local perma_color, non_perma_color = Color( 255, 0, 0 ), Color( 0, 255, 0 )
    hook.Add( "PostDrawTranslucentRenderables", "vkx_entspawner:spawners", function( is_depth, is_skybox )
        if is_skybox then return end
        if not vkx_entspawner.is_holding_tool() then return end

        local tool = vkx_entspawner.get_tool()
        if not tool then return end

        for i, v in ipairs( tool.preview_locations ) do
            preview_model:SetRenderOrigin( v.pos )
            preview_model:SetRenderAngles( v.ang )
            preview_model:SetupBones()
            preview_model:DrawModel()
        end

        --  draw spawners
        for i, spawner in ipairs( vkx_entspawner.spawners ) do
            --  spawners
            for i, v in ipairs( spawner.locations ) do
                local color = spawner.perma and perma_color or non_perma_color
                render.DrawWireframeSphere( v.pos, min_dist, 6, 6, color, false )
                render.DrawLine( v.pos, v.pos + v.ang:Forward() * min_dist * 1.5, color, false )
            end
            
            --  player radius
            if ( spawner.radius or 0 ) > 0 then
                render.DrawWireframeSphere( vkx_entspawner.get_spawner_center( spawner ), spawner.radius, 6, 6, spawner.radius_disappear and perma_color or non_perma_color, true )
            end
        end

        --  draw radius preview
        local tool = vkx_entspawner.get_tool()
        local radius, radius_disappear = tool:GetClientNumber( "spawner_radius", 0 ), tool:GetClientInfo( "spawner_radius_disappear" ) == "1"
        if radius > 0 then
            local locations = {}
            for i, ent in ipairs( tool.preview_locations ) do
                locations[i] = {
                    pos = ent.pos
                }
            end

            render.DrawWireframeSphere( vkx_entspawner.get_spawner_center( { locations = locations } ), radius, 6, 6, radius_disappear and perma_color or non_perma_color, true )
        end
    end )

    hook.Add( "HUDPaint", "vkx_entspawner:spawners", function()
        if not vkx_entspawner.is_holding_tool() then return end

        --  spawners
        local tr_pos = LocalPlayer():GetEyeTrace().HitPos
        for i, spawner in ipairs( vkx_entspawner.spawners ) do
            for i, v in ipairs( spawner.locations ) do
                if tr_pos:DistToSqr( v.pos ) <= min_dist_sqr then
                    local color = spawner.perma and perma_color or non_perma_color
                    local pos = v.pos:ToScreen()
                    
                    draw.SimpleText( spawner.delay .. "s ─ " .. spawner.max .. " max", "Default", pos.x, pos.y, color )
                    for i, ent in ipairs( spawner.entities ) do
                        draw.SimpleText( ent.key .. " (" .. ent.percent * 100 .. "%)", "Default", pos.x, pos.y + 15 * i, color )
                    end
                end
            end
        end
    end )

    --  menu
    local shape_setups = {
        ["Int"] = function( panel, k, v )
            panel:NumSlider( v.name or k, "vkx_entspawner_" .. k, v.template.options.min, v.template.options.max, 0 )
        end,
        ["Float"] = function( panel, k, v )
            panel:NumSlider( v.name or k, "vkx_entspawner_" .. k, v.template.options.min, v.template.options.max, v.template.options.decimals or 2 )
        end,
        ["Boolean"] = function( panel, k, v )
            panel:CheckBox( v.name or k, "vkx_entspawner_" .. k )
        end,
    }
    function TOOL.BuildCPanel( panel )
        --  presets
        local preset_control
        if vkx_presets then
            preset_control = vgui.Create( "VKXPresetControl", panel )
            preset_control:Dock( TOP )
            preset_control:SetCategory( "vkx_entspawner" )
            panel.Items[#panel.Items + 1] = preset_control --  needed to be cleared
        end

        ---   shape
        local shape_form = vgui.Create( "DForm" )
        shape_form:SetName( "Shape" )
        panel:AddItem( shape_form )
        
        local convar = GetConVar( "vkx_entspawner_shape" )
        local shape_combobox = shape_form:ComboBox( "Type" )
        for k in SortedPairsByMemberValue( list.Get( "vkx_entspawner_shapes" ), "z_order" ) do
            shape_combobox:AddChoice( k, nil, k == convar:GetString() )
        end
        function shape_combobox:OnSelect( id, value )
            for i, v in ipairs( shape_form.Items ) do
                if i > 2 then 
                    v:Remove()
                end
            end
            convar:SetString( value )
            
            --  refresh locations
            vkx_entspawner.refresh_tool_preview()
            
            --  menu setup
            local shape = list.Get( "vkx_entspawner_shapes" )[value]
            if shape.setup then return shape.setup( shape_form ) end
            
            --  auto setup
            local setuped = false
            for k, v in SortedPairsByMemberValue( shape.convars or {}, "z_order" ) do
                if v.template and shape_setups[v.template.type] then
                    shape_setups[v.template.type]( shape_form, k, v )
                    setuped = true
                end
            end

            if not setuped then
                shape_form:Help( "No settings!" )
            end
        end
        shape_form:ControlHelp( "Represents the placement of spawners." )
        shape_combobox:SetSortItems( false )
        shape_combobox:OnSelect( 1, convar:GetString() )
        
        ---   entities
        local entities_form = vgui.Create( "DForm" )
        entities_form:SetName( "Entities" )
        panel:AddItem( entities_form )
        
        entities_form:Help( "Available Entities" )
        local entities_sheets, selected_list = vgui.Create( "DPropertySheet" )
        entities_sheets:SetTall( 175 )
        entities_form:AddItem( entities_sheets )
        
        local function add_sheet( name, icon )
            local list_view = vgui.Create( "DListView" )
            list_view:SetMultiSelect( false )
            list_view:SetTall( 150 )
            list_view:AddColumn( "Name" )
            list_view:AddColumn( "Category" )
            list_view:AddColumn( "Key" )
            function list_view:DoDoubleClick( id, panel )
                selected_list:AddLine( panel:GetColumnText( 1 ), panel:GetColumnText( 2 ), panel:GetColumnText( 3 ) )
            end
            function list_view:OnRowRightClick( id, panel )
                local menu = DermaMenu( panel )
                menu:AddOption( "Add", function()
                    self:DoDoubleClick( id, panel )    
                end ):SetMaterial( "icon16/add.png" )
                menu:Open()
            end
            entities_sheets:AddSheet( name, list_view, icon )
            
            return list_view
        end
        

        --  cache category, name & key of entities present in `vkx_entspawner.ents_chance` to add them just after 
        local cache_ents_chance_lines = {}
        local function cache_ents_chance_data( key, name, category )
            if #vkx_entspawner.ents_chance - #cache_ents_chance_lines <= 0 then return end

            for i, v in ipairs( vkx_entspawner.ents_chance ) do
                if v.key == key then
                    cache_ents_chance_lines[#cache_ents_chance_lines + 1] = {
                        key = key,
                        name = name,
                        category = category,
                    }
                    return
                end
            end
        end

        --  weapons
        local weapons_list = add_sheet( "Weapons", "icon16/gun.png" )
        for k, v in pairs( list.Get( "Weapon" ) ) do
            if v.Spawnable then
                local category = v.Category or "Other"
                weapons_list:AddLine( v.PrintName, category, k )
                cache_ents_chance_data( k, v.PrintName, category )
            end
        end
        weapons_list:SortByColumn( 2 )
        
        --  entities
        local entities_list = add_sheet( "Entities", "icon16/bricks.png" )
        for k, v in pairs( list.Get( "SpawnableEntities" ) ) do
            local category = v.Category or "Other"
            entities_list:AddLine( v.PrintName, category, k )
            cache_ents_chance_data( k, v.PrintName, category )
        end
        entities_list:SortByColumn( 2 )
        
        --  npcs
        local npcs_list = add_sheet( "NPCs", "icon16/monkey.png" )
        for k, v in pairs( list.Get( "NPC" ) ) do
            npcs_list:AddLine( v.Name, v.Category, k )
            cache_ents_chance_data( k, v.Name, v.Category )
        end
        npcs_list:SortByColumn( 2 )
        
        --  vehicles
        local vehicles_list = add_sheet( "Vehicles", "icon16/car.png" )
        for k, v in pairs( list.Get( "Vehicles" ) ) do
            vehicles_list:AddLine( v.Name, v.Category, k )
            cache_ents_chance_data( k, v.Name, v.Category )
        end
        vehicles_list:SortByColumn( 2 )
        
        --  simfphys
        if simfphys then
            local simfphys_list = add_sheet( "simfphys", "icon16/car.png" )
            for k, v in pairs( list.Get( "simfphys_vehicles" ) ) do
                simfphys_list:AddLine( v.Name, v.Category, k )
                cache_ents_chance_data( k, v.Name, v.Category )
            end
            simfphys_list:SortByColumn( 2 )
        end
        
        --  selected
        local chance_slider
        entities_form:Help( "Selected Entities" )
        selected_list = vgui.Create( "DListView" )
        selected_list:SetMultiSelect( false )
        selected_list:SetTall( 150 )
        selected_list:AddColumn( "Name" )
        selected_list:AddColumn( "Category" )
        selected_list:AddColumn( "Key" )
        function selected_list:OnRowSelected( id, panel )
            chance_slider:SetValue( vkx_entspawner.ents_chance[id] and vkx_entspawner.ents_chance[id].percent * 100 or 100 )
        end
        function selected_list:OnRowRightClick( id, panel )
            local menu = DermaMenu( panel )
            menu:AddOption( "Remove", function()
                vkx_entspawner.ents_chance[id] = nil
                selected_list:RemoveLine( id )
            end ):SetMaterial( "icon16/delete.png" )
            menu:AddOption( "Remove all", function()
                vkx_entspawner.ents_chance = {}
                self:Clear()
            end ):SetMaterial( "icon16/arrow_refresh.png" )
            menu:Open()
        end
        local add_line = selected_list.AddLine
        function selected_list:AddLine( name, category, key )
            --  check if exists
            for i, v in ipairs( self.Lines ) do
                if v:GetColumnText( 3 ) == key then 
                    return 
                end
            end
            
            add_line( self, name, category, key )
            vkx_entspawner.ents_chance[#self.Lines] = {
                percent = 1,
                key = key,
            }
        end
        entities_form:AddItem( selected_list )

        --  add cached list
        for i, v in ipairs( cache_ents_chance_lines ) do
            add_line( selected_list, v.name, v.category, v.key )
        end
        
        --  chance slider
        chance_slider = entities_form:NumSlider( "Spawn Chance (%)", nil, 0, 100, 0 )
        function chance_slider:Think()
            self:SetEnabled( selected_list:GetSelectedLine() )
        end
        function chance_slider:OnValueChanged( value )
            local id, selected = selected_list:GetSelectedLine()
            if not selected or not vkx_entspawner.ents_chance[id] then return end
            vkx_entspawner.ents_chance[id].percent = math.Round( value / 100, 2 )
        end
        entities_form:ControlHelp( "Chance to spawn for the selected Entity. Note that the script will simulate the chance from the first to the last NPC of the list. However it will stop if the chance success (so avoid putting 100% chance at the top list)." )
        
        ---   spawner
        local spawner_form = vgui.Create( "DForm" )
        spawner_form:SetName( "Spawner" )
        panel:AddItem( spawner_form )
        
        local spawner_check, perma_check, max_slider, delay_slider, radius_slider = spawner_form:CheckBox( "Is Spawner", "vkx_entspawner_is_spawner" )
        spawner_form:ControlHelp( "If checked, this tool will creates Entities Spawners instead of direct Entities." )
        function spawner_check:OnChange( value )
            for i, v in ipairs( spawner_form.Items ) do
                v:SetEnabled( value )
            end
        end
        
        --  perma
        perma_check = spawner_form:CheckBox( "Is Perma", "vkx_entspawner_is_perma" )
        spawner_form:ControlHelp( "If checked, the created Entities spawners will be saved and loaded on server start. Note that red sphere spawners represent perma spawners and green are non-perma spawners." )
        
        --  max
        local options = vkx_entspawner.template:get( "spawner_max" ):get_options()
        max_slider = spawner_form:NumSlider( "Max Entities", "vkx_entspawner_spawner_max", options.min, options.max, 0 )
        spawner_form:ControlHelp( "How many Entities can spawn for each spawner/location?" )
        
        --  delay
        local options = vkx_entspawner.template:get( "spawner_delay" ):get_options()
        delay_slider = spawner_form:NumSlider( "Spawn Delay", "vkx_entspawner_spawner_delay", options.min, options.max, 0 )
        spawner_form:ControlHelp( "How many seconds should the spawner wait between each spawn?" )
        
        --  radius
        local options = vkx_entspawner.template:get( "spawner_radius" ):get_options()
        radius_slider = spawner_form:NumSlider( "Player Spawn Radius", "vkx_entspawner_spawner_radius", options.min, options.max, 0 )
        spawner_form:ControlHelp( "If set above 0, the radius will define the area whenever the spawner will start to spawn entities depending of player presence. If a player is in the radius, the spawner will start spawning." )
        
        --  radius disappear
        radius_disappear_check = spawner_form:CheckBox( "Player Disappear Radius", "vkx_entspawner_spawner_radius_disappear" )
        spawner_form:ControlHelp( "If checked, when no player is within the radius, spawned entities will automatically disappear." )
        
        spawner_check:OnChange( spawner_check:GetChecked() )

        --  presets
        if vkx_presets then
            preset_control:RegisterCallback( "shape", 
                function( value )
                    for i, v in ipairs( shape_combobox.Choices ) do
                        if v == value then
                            shape_combobox:ChooseOption( value, i )
                            return
                        end
                    end
                end,
                function()
                    return shape_combobox:GetSelected() 
                end
            )
            preset_control:RegisterCallback( "ents_chance",
                function( chances )
                    vkx_entspawner.ents_chance = table.Copy( chances )
                    selected_list:Clear()

                    for i, chance in pairs( chances ) do
                        local breaked = false

                        for i, sheet in ipairs( entities_sheets.Items ) do
                            for i, line in ipairs( sheet.Panel:GetLines() ) do
                                if line:GetValue( 3 ) == chance.key then
                                    add_line( selected_list, line:GetValue( 1 ), line:GetValue( 2 ), line:GetValue( 3 ) )
                                    breaked = true
                                    break
                                end
                            end

                            if breaked then 
                                break 
                            end
                        end
                    end
                end,
                function()
                    return vkx_entspawner.ents_chance
                end
            )

            for convar in pairs( convars ) do
                preset_control:RegisterConVar( convar:gsub( "vkx_entspawner_", "" ), convar )
            end
        end
    end

    function TOOL:RebuildCPanel()
        local panel = controlpanel.Get( self.Mode )
        if not panel then vkx_entspawner.print( "Unable to rebuild the control panel of the tool : not found!" ) end

        panel:ClearControls()
        self.BuildCPanel( panel )
    end
end



--  register convars
local template = vkx_presets and vkx_presets.new_template( "vkx_entspawner" )
local function add_convar( k, v, template_type, template_options )
    TOOL.ClientConVar[k] = v
    if CLIENT then
        cvars.AddChangeCallback( TOOL.Mode .. "_" .. k, vkx_entspawner.refresh_tool_preview, "VKXTool" )
        vkx_entspawner.print( "Register %q (default: %q)", TOOL.Mode .. "_" .. k, v )

        if template then
            local keyvalue = template:add( k, v )
            if template_type then keyvalue:as( template_type, template_options ) end
        end
    end
end

--  shapes
local shapes = list.Get( "vkx_entspawner_shapes" )
local values = {}
for k, v in pairs( shapes ) do
    values[k] = k
end
add_convar( "shape", "None", "Combo", { values = values } )

--  others
add_convar( "is_spawner", "0", "Boolean" )
add_convar( "is_perma", "0", "Boolean" )
add_convar( "spawner_max", "1", "Int", { min = 1, max = 16 } )
add_convar( "spawner_delay", "3", "Int", { min = 1, max = 120 } )
add_convar( "spawner_radius", "0", "Int", { min = 0, max = 2 ^ 16 - 1 } )
add_convar( "spawner_radius_disappear", "0", "Boolean" )

for k, v in pairs( shapes ) do
    for cmd_k, cmd_v in pairs( v.convars or {} ) do
        add_convar( cmd_k, cmd_v.default, cmd_v.template and cmd_v.template.type, cmd_v.template and cmd_v.template.options )
    end
end

if template then
    template:add( "ents_chance", {} )
    template:build_default_preset()
    vkx_entspawner.template = template
end

convars = TOOL:BuildConVarList()