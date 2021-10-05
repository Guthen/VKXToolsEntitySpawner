TOOL.Category = "VKX Tools"
TOOL.Name = "#tool.vkx_entspawner.name"

TOOL.model = "models/editor/playerstart.mdl"

local convars
function TOOL:LeftClick( tr )
    if SERVER then return true end

    if not self.ghost_entities or #self.ghost_entities == 0 then return false end
    if not vkx_entspawner.ents_chance or table.Count( vkx_entspawner.ents_chance ) == 0 then 
        notification.AddLegacy( "You must have selected entities to spawn!", NOTIFY_ERROR, 3 )
        return true
    end

    local locations = {}
    for i, v in ipairs( self.ghost_entities ) do
        locations[#locations + 1] = {
            pos = v:GetPos(),
            ang = v:GetAngles(),
        }
    end

    local is_spawner = tobool( self:GetClientNumber( "is_spawner", 0 ) )
    net.Start( "vkx_entspawner:spawn" )
        net.WriteTable( locations )
        net.WriteTable( table.ClearKeys( vkx_entspawner.ents_chance ) )
        net.WriteBool( is_spawner )
        if is_spawner then
            net.WriteBool( tobool( self:GetClientNumber( "is_perma", 0 ) ) )
            net.WriteUInt( self:GetClientNumber( "spawner_max", 1 ), 8 )
            net.WriteUInt( self:GetClientNumber( "spawner_delay", 3 ), 10 )
            net.WriteUInt( self:GetClientNumber( "spawner_radius", 0 ), 16 )
            net.WriteBool( self:GetClientNumber( "spawner_radius_disappear", 0 ) )
        end
    net.SendToServer()

    return true
end

local min_dist = 32
local min_dist_sqr = min_dist ^ 2
function TOOL:RightClick( tr )
    if CLIENT then return true end

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
        
        local locations = net.ReadTable()
        if not locations or #locations == 0 then 
            return vkx_entspawner.debug_print( "%q didn't send locations", ply:GetName() ) 
        end

        local chances = net.ReadTable()
        if not chances or #chances == 0 then 
            return vkx_entspawner.debug_print( "%q didn't send chances", ply:GetName() ) 
        end

        local is_spawner, is_perma, spawner_max, spawner_delay, spawner_radius, spawner_radius_disappear = net.ReadBool()
        if is_spawner then
            is_perma = net.ReadBool()
            spawner_max = net.ReadUInt( 8 )
            spawner_delay = net.ReadUInt( 10 )
            spawner_radius = net.ReadUInt( 16 )
            spawner_radius_disappear = net.ReadBool()

            local id = vkx_entspawner.new_spawners( locations, chances, spawner_max, spawner_delay, is_perma, spawner_radius, spawner_radius_disappear )
            if not is_perma then 
                undo.Create( "Entities Spawners" )
                undo.AddFunction( function()
                    vkx_entspawner.delete_spawner( id )
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
    language.Add( "tool.vkx_entspawner.reload", "Re-generate locations" )

    --  ghost entities
    vkx_entspawner.delete_ghost_entities()  --  auto-refresh
    TOOL.ghost_entities = {}
    function TOOL:AddGhostEntity( pos, ang )
        local ent = ClientsideModel( self.model, RENDERMODE_TRANSCOLOR )
        if not IsValid( ent ) then return end
        if pos then ent:SetPos( pos ) end
        if ang then ent:SetAngles( ang ) end
        ent:SetColor( Color( 255, 255, 255, 150 ) )
        ent:Spawn()

        self.ghost_entities[#self.ghost_entities + 1] = ent
    end

    function TOOL:ClearGhostEntities()
        for i, v in ipairs( self.ghost_entities ) do
            v:Remove()
        end
        self.ghost_entities = {}
    end

    function TOOL:UpdateGhostEntities( pos )
        if not self.locations and self:ComputeGhostEntities() then return end

        local ang = Angle( 0, ( LocalPlayer():GetPos() - pos ):Angle().y, 0 )
        for i, v in ipairs( self.locations ) do
            if self.ghost_entities[i] then
                --  some client entities might be removed so we create it again to avoid errors
                if not IsValid( self.ghost_entities[i] ) then
                    self:ClearGhostEntities()
                    self:ComputeGhostEntities()
                    break
                end

                --  rotate position
                local rotated_pos = Vector( v.pos:Unpack() )
                rotated_pos:Rotate( ang )

                --  compute final position and angle
                self.ghost_entities[i]:SetPos( pos + rotated_pos )
                self.ghost_entities[i]:SetAngles( ang + v.ang )
            end
        end
    end

    function TOOL:ComputeGhostEntities()
        local shapes, shape = list.Get( "vkx_entspawner_shapes" ), self:GetClientInfo( "shape" )
        if not shapes[shape] or not shapes[shape].compute then return false end

        local locations = shapes[shape].compute( self )
        if not locations then return false end

        --  create new ghosts
        for i, v in ipairs( locations ) do
            if not self.ghost_entities[i] then
                self:AddGhostEntity( v.pos, v.ang )
            end
        end
        self.locations = locations

        --  clear other ghosts
        for i = #locations + 1, #self.ghost_entities do
            self.ghost_entities[i]:Remove()
            self.ghost_entities[i] = nil
        end 

        return true
    end

    function TOOL:Think()
        if #self.ghost_entities == 0 then
            self:ComputeGhostEntities()
        end
        self:UpdateGhostEntities( self:GetOwner():GetEyeTrace().HitPos )
    end

    function TOOL:Reload( tr )
        self:ComputeGhostEntities()
        return true
    end

    function TOOL:Holster()
        self:ClearGhostEntities()
    end

    --  draw spawners
    local perma_color, non_perma_color = Color( 255, 0, 0 ), Color( 0, 255, 0 )
    hook.Add( "PostDrawTranslucentRenderables", "vkx_entspawner:spawners", function()
        if not vkx_entspawner.is_holding_tool() then return end

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

        --  radius preview
        local tool = vkx_entspawner.get_tool()
        local radius, radius_disappear = tool:GetClientNumber( "spawner_radius", 0 ), tool:GetClientInfo( "spawner_radius_disappear" ) == "1"
        if radius > 0 then
            local locations = {}
            for i, ent in ipairs( tool.ghost_entities ) do
                locations[i] = {
                    pos = ent:GetPos()
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
                        draw.SimpleText( ent.key .. " (" .. ent.percent .. "%)", "Default", pos.x, pos.y + 15 * i, color )
                    end
                end
            end
        end
    end )

    --  menu
    function TOOL.BuildCPanel( panel )
        panel:AddControl( "ComboBox", {
            MenuButton = 1,
            Folder = "vkx_entspawner",
            Options = {
                ["#preset.default"] = convars,
            },
            CVars = table.GetKeys( convars ),
        } )

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
            if not ( shape.setup ) then return shape_form:Help( "No settings!" ) end

            shape.setup( shape_form )
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

        --  weapons
        local weapons_list = add_sheet( "Weapons", "icon16/gun.png" )
        for k, v in pairs( list.Get( "Weapon" ) ) do
            if v.Spawnable then
                weapons_list:AddLine( v.PrintName, v.Category or "Other", k )
            end
        end
        weapons_list:SortByColumn( 2 )

        --  entities
        local entities_list = add_sheet( "Entities", "icon16/bricks.png" )
        for k, v in pairs( list.Get( "SpawnableEntities" ) ) do
            entities_list:AddLine( v.PrintName, v.Category or "Other", k )
        end
        entities_list:SortByColumn( 2 )

        --  npcs
        local npcs_list = add_sheet( "NPCs", "icon16/monkey.png" )
        for k, v in pairs( list.Get( "NPC" ) ) do
            npcs_list:AddLine( v.Name, v.Category, k )
        end
        npcs_list:SortByColumn( 2 )

        --  vehicles
        local vehicles_list = add_sheet( "Vehicles", "icon16/car.png" )
        for k, v in pairs( list.Get( "Vehicles" ) ) do
            vehicles_list:AddLine( v.Name, v.Category, k )
        end
        vehicles_list:SortByColumn( 2 )

        --  simfphys
        if simfphys then
            local simfphys_list = add_sheet( "simfphys", "icon16/car.png" )
            for k, v in pairs( list.Get( "simfphys_vehicles" ) ) do
                simfphys_list:AddLine( v.Name, v.Category, k )
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
            chance_slider:SetValue( vkx_entspawner.ents_chance[id] and vkx_entspawner.ents_chance[id].percent or 100 )
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
                percent = 100,
                key = key,
            }
        end
        entities_form:AddItem( selected_list )

        --  chance slider
        vkx_entspawner.ents_chance = {}
        chance_slider = entities_form:NumSlider( "Spawn Chance (%)", nil, 0, 100, 0 )
        function chance_slider:Think()
            self:SetEnabled( selected_list:GetSelectedLine() )
        end
        function chance_slider:OnValueChanged( value )
            local id, selected = selected_list:GetSelectedLine()
            if not selected or not vkx_entspawner.ents_chance[id] then return end
            vkx_entspawner.ents_chance[id].percent = value
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
        max_slider = spawner_form:NumSlider( "Max Entities", "vkx_entspawner_spawner_max", 1, 16, 0 )
        spawner_form:ControlHelp( "How many Entities can spawn for each spawner/location?" )

        --  delay
        delay_slider = spawner_form:NumSlider( "Spawn Delay", "vkx_entspawner_spawner_delay", 1, 120, 0 )
        spawner_form:ControlHelp( "How many seconds should the spawner wait between each spawn?" )

        --  radius
        radius_slider = spawner_form:NumSlider( "Player Spawn Radius", "vkx_entspawner_spawner_radius", 0, 2 ^ 16 - 1, 0 )
        spawner_form:ControlHelp( "If set above 0, the radius will define the area whenever the spawner will start to spawn entities depending of player presence. If a player is in the radius, the spawner will start spawning." )

        --  radius disappear
        radius_disappear_check = spawner_form:CheckBox( "Player Disappear Radius", "vkx_entspawner_spawner_radius_disappear" )
        spawner_form:ControlHelp( "If checked, when no player is within the radius, spawned entities will automatically disappear." )

        spawner_check:OnChange( spawner_check:GetChecked() )
    end
end



--  register convars
local function add_convar( k, v )
    TOOL.ClientConVar[k] = v
    if CLIENT then
        cvars.AddChangeCallback( TOOL.Mode .. "_" .. k, vkx_entspawner.refresh_tool_preview, "VKXTool" )
        vkx_entspawner.print( "Register %q (default: %q)", TOOL.Mode .. "_" .. k, v )
    end
end

add_convar( "shape", "None" )
add_convar( "is_spawner", "0" )
add_convar( "is_perma", "0" )
add_convar( "spawner_max", "1" )
add_convar( "spawner_delay", "3" )
add_convar( "spawner_radius", "0" )
add_convar( "spawner_radius_disappear", "0" )

for k, v in pairs( list.Get( "vkx_entspawner_shapes" ) ) do
    for cmd_k, cmd_v in pairs( v.convars or {} ) do
        add_convar( cmd_k, cmd_v )
    end
end

convars = TOOL:BuildConVarList()