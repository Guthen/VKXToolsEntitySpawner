vkx_entspawner = vkx_entspawner or {}
vkx_entspawner.version = "2.7.0"
vkx_entspawner.save_path = "vkx_tools/entspawners/%s.json"
vkx_entspawner.spawners = vkx_entspawner.spawners or {}
vkx_entspawner.blocking_entity_blacklist = {
    ["keyframe_rope"] = true,
    ["move_rope"] = true,
    ["trigger_multiple"] = true,
    ["trigger_once"] = true,

    ["physgun_beam"] = true,
    ["predicted_viewmodel"] = true,
}

--  network limitations
vkx_entspawner.NET_SPAWNER_ID_BITS = 8 --  default: 8 (unsigned) bytes which allows 255 different locations
vkx_entspawner.NET_SPAWNER_LOCATIONS_BITS = 10 --  default: 10 (unsigned) bytes which allows 1023 different locations
vkx_entspawner.NET_SPAWNER_ENTS_CHANCE_BITS = 5 --  default: 5 (unsigned) bytes which allows 31 different entities
vkx_entspawner.NET_SPAWNERS_BITS = 16 --  default: 16 (unsigned) bytes which allows 65535 different spawners
vkx_entspawner.NET_SPAWNER_MAX_ENTITIES_BITS = 8 --  default: 8 (unsigned) bytes which allows networking up to 255 values
vkx_entspawner.NET_SPAWNER_DELAY_BITS = 16 --  default: 16 (unsigned) bytes which allows networking up to 65535 seconds (18 hours)
vkx_entspawner.NET_SPAWNER_RADIUS_BITS = 16 --  default: 16 (unsigned) bytes which allows networking up to 65535 units
vkx_entspawner.NET_SPAWNER_RUN_TIMES_BITS = 16 --  default: 16 (unsigned) bytes which allows networking up to 65535 values

function vkx_entspawner.print( msg, ... )
    if #{ ... } > 0 then
        print( "VKX Entity Spawner ─ " .. msg:format( ... ) )
    else
        print( "VKX Entity Spawner ─ " .. msg )
    end
end

local convar_debug = CreateConVar( "vkx_entspawner_debug", "0", FCVAR_ARCHIVE, "enables debug messages", 0, 1 )
function vkx_entspawner.is_debug()
    return convar_debug:GetBool()
end

function vkx_entspawner.debug_print( msg, ... )
    if not vkx_entspawner.is_debug() then return end
    vkx_entspawner.print( "Debug: " .. msg, ... )
end

function vkx_entspawner.get_spawner_center( spawner )
    local sum_pos = Vector()

    for i, v in ipairs( spawner.locations ) do
        sum_pos = sum_pos + v.pos
    end

    return sum_pos / #spawner.locations
end

if CLIENT then
    vkx_entspawner.ents_chance = vkx_entspawner.ents_chance or {}
    vkx_entspawner.ents_data_cache = vkx_entspawner.ents_data_cache or {}

    function vkx_entspawner.cache_entity_data( key, name, category )
        vkx_entspawner.ents_data_cache[key] = {
            key = key,
            name = name,
            category = category,
        }
    end

    function vkx_entspawner.is_holding_tool()
        if not IsValid( LocalPlayer() ) then return false end 

        local weapon = LocalPlayer():GetActiveWeapon()
        if not IsValid( weapon ) or not ( weapon:GetClass() == "gmod_tool" ) or not ( weapon:GetMode() == "vkx_entspawner" ) then return false end

        return true
    end

    function vkx_entspawner.get_tool()
        if not IsValid( LocalPlayer() ) then return end
        return LocalPlayer():GetTool( "vkx_entspawner" )
    end

    function vkx_entspawner.refresh_tool_preview()
        local tool = vkx_entspawner.get_tool()
        if tool then
            tool:ComputePreviewLocations()
        end
    end

    function vkx_entspawner.delete_preview_locations()
        local tool = vkx_entspawner.get_tool()
        if tool then
            tool:ClearPreviewLocations()
        end
    end

    --  network spawners
    net.Receive( "vkx_entspawner:network", function( len )
        local spawners = {}

        for i = 1, net.ReadUInt( vkx_entspawner.NET_SPAWNERS_BITS ) do
            local spawner = {}
            spawner.id = net.ReadUInt( vkx_entspawner.NET_SPAWNER_ID_BITS )
            spawner.perma = net.ReadBool()
            spawner.oneshot = net.ReadBool()
            
            --  locations
            spawner.locations = {}
            for k = 1, net.ReadUInt( vkx_entspawner.NET_SPAWNER_LOCATIONS_BITS ) do
                spawner.locations[k] = {
                    pos = net.ReadVector(),
                    ang = net.ReadAngle(),
                    entities = {},
                }
            end

            --  entities chance
            spawner.entities = {}
            for k = 1, net.ReadUInt( vkx_entspawner.NET_SPAWNER_ENTS_CHANCE_BITS ) do
                spawner.entities[k] = {
                    key = net.ReadString(),
                    percent = math.Round( net.ReadFloat(), 2 ),
                }
            end

            spawner.max = net.ReadUInt( vkx_entspawner.NET_SPAWNER_MAX_ENTITIES_BITS )
            spawner.delay = net.ReadUInt( vkx_entspawner.NET_SPAWNER_DELAY_BITS )
            spawner.radius = net.ReadUInt( vkx_entspawner.NET_SPAWNER_RADIUS_BITS )
            spawner.radius_disappear = net.ReadBool()
            spawner.last_time = net.ReadFloat()
            spawner.run_times = net.ReadUInt( vkx_entspawner.NET_SPAWNER_RUN_TIMES_BITS )

            spawners[spawner.id] = spawner
        end

        vkx_entspawner.spawners = spawners
        vkx_entspawner.debug_print( "received %d spawners (%s bits/%s)", #spawners, len, string.NiceSize( len / 8 ) )
    end )

    net.Receive( "vkx_entspawner:run", function( len )
        local id = net.ReadUInt( vkx_entspawner.NET_SPAWNER_ID_BITS )

        --  find spawner
        local spawner = vkx_entspawner.spawners[id]
        if not spawner then
            vkx_entspawner.debug_print( "couldn't receive spawner %d run (%s bits/%s): not found!", id, len, string.NiceSize( len / 8 ) )
            return
        end

        --  set values
        spawner.last_time = net.ReadFloat()
        spawner.run_times = net.ReadUInt( vkx_entspawner.NET_SPAWNER_RUN_TIMES_BITS )

        --  read active entities
        for i, v in ipairs( spawner.locations ) do
            local count = net.ReadUInt( vkx_entspawner.NET_SPAWNER_MAX_ENTITIES_BITS )

            v.entities = {}
            for i = 1, count do
                v.entities[i] = net.ReadEntity()
            end
        end

        vkx_entspawner.debug_print( "received spawner %d run (%s bits/%s)", id, len, string.NiceSize( len / 8 ) )
    end )

    local function retrieve_spawners()
        net.Start( "vkx_entspawner:network" )
        net.SendToServer()
    end
    concommand.Add( "vkx_entspawner_retrieve_spawners", retrieve_spawners )
    hook.Add( "InitPostEntity", "vkx_entspawner:network", retrieve_spawners )

    --  notification
    net.Receive( "vkx_entspawner:notify", function()
        notification.AddLegacy( net.ReadString(), net.ReadUInt( 3 ), 3 )
    end )
else
    --  convars
    local convar_network_admin_only = CreateConVar( "vkx_entspawner_network_superadmin_only", 1, { FCVAR_ARCHIVE, FCVAR_LUA_SERVER }, "Should the spawners be networked to superadmin only or be available for other players?", 0, 1 )
    local convar_network_run = CreateConVar( "vkx_entspawner_network_run", 0, { FCVAR_ARCHIVE, FCVAR_LUA_SERVER }, "Should the spawners run-time be networked to allowed users? This option syncs the new spawner properties to clients. Users are defined by 'vkx_entspawner_network_superadmin_only' convar", 0, 1 )
    
    --  cache spawned entities
    local is_spawnlist_registering, entities_spawnlist = false, {}
    hook.Add( "OnEntityCreated", "vkx_entspawner:can_spawn_safely", function( ent )
        if is_spawnlist_registering then
            entities_spawnlist[ent] = true
        end
    end )

    --  using `list.GetForEdit` so we use the pointer to the list instead of a copy (allowing further changes to lists)
    local cached_lists = {
        Weapon = list.GetForEdit( "Weapon" ),
        NPC = list.GetForEdit( "NPC" ),
        SpawnableEntities = list.GetForEdit( "SpawnableEntities" ),
        Vehicles = list.GetForEdit( "Vehicles" ),
        simfphys_vehicles = list.GetForEdit( "simfphys_vehicles" ),
    }
    function vkx_entspawner.spawn_object( key, pos, ang )
        if not key or not pos or not ang then return end

        is_spawnlist_registering = true
        entities_spawnlist = {}

        local obj, cat
        if cached_lists.Weapon[key] then
            obj, cat = vkx_entspawner.spawn_weapon( key, pos, ang )
        elseif cached_lists.NPC[key] then
            obj, cat = vkx_entspawner.spawn_npc( key, pos, ang )
        elseif scripted_ents.GetStored( key ) then
            obj, cat = vkx_entspawner.spawn_sent( key, pos, ang )
        elseif cached_lists.SpawnableEntities[key] then
            obj, cat = vkx_entspawner.spawn_entity( key, pos, ang )
        elseif cached_lists.Vehicles[key] then
            obj, cat = vkx_entspawner.spawn_vehicle( key, pos, ang )
        elseif simfphys and cached_lists.simfphys_vehicles[key] then
            local vehicle = cached_lists.simfphys_vehicles[key]
            if vehicle.SpawnOffset then 
                pos = pos + vehicle.SpawnOffset 
            end
            obj, cat = simfphys.SpawnVehicleSimple( key, pos, ang ), "vehicles"
        else
            obj, cat = vkx_entspawner.print( "Try to spawn an Object %q which is not supported!", key )
        end

        is_spawnlist_registering = false

        return obj, cat
    end

    function vkx_entspawner.spawn_vehicle( key, pos, ang )
        local vehicle = cached_lists.Vehicles[key]
        if not vehicle then 
            return vkx_entspawner.print( "Try to spawn a Vehicle %q which doesn't exists!", key )
        end

        local ent = ents.Create( vehicle.Class )
        if not IsValid( ent ) then 
            return vkx_entspawner.print( "Failed to create %q for unknown reasons!", vehicle.Name ) 
        end
        if vehicle.Offset then pos = Vector( pos.x, pos.y, pos.z + vehicle.Offset ) end
        ent:SetPos( pos )
        ent:SetAngles( ang )
        if vehicle.Model then ent:SetModel( vehicle.Model ) end
        for k, v in pairs( vehicle.KeyValues or {} ) do
            ent:SetKeyValue( k, v )
        end
        ent:Spawn()

        return ent, "vehicles"
    end

    function vkx_entspawner.spawn_sent( key, pos, ang )
        local sent = scripted_ents.GetStored( key )
        if not sent then
            return vkx_entspawner.print( "Try to spawn a SENT %q which doesn't exists!", key )
        end

        local spawn_function = scripted_ents.GetMember( key, "SpawnFunction" )
        if not spawn_function then 
            return vkx_entspawner.spawn_entity( key, pos, ang ) 
        end

        local tr = util.TraceLine( {
            start = pos,
            endpos = pos - Vector( 0, 0, 1 ),
        } )

        ClassName = key
        local success, ent = pcall( spawn_function, sent, NULL, tr, key ) --  as we don't have a valid player to give and that some entities might use ply, we have to be carefull
        ClassName = nil

        if success and IsValid( ent ) then
            return ent, "sents"
        else
            return vkx_entspawner.spawn_entity( key, pos, ang )
        end
    end

    function vkx_entspawner.spawn_entity( key, pos, ang )
        local entity = cached_lists.SpawnableEntities[key]
        if not entity then
            return vkx_entspawner.print( "Try to spawn an Entity %q which doesn't exists!", key )
        end

        local ent = ents.Create( entity.ClassName )
        if not IsValid( ent ) then
            return vkx_entspawner.print( "Failed to create %q for unknow reasons!", weapon.PrintName )
        end
        ent:SetPos( pos )
        ent:SetAngles( ang )
        ent:Spawn()

        return ent, "sents"
    end

    function vkx_entspawner.spawn_weapon( key, pos, ang )
        local weapon = cached_lists.Weapon[key]
        if not weapon then
            return vkx_entspawner.print( "Try to spawn a Weapon %q which doesn't exists!", key )
        end

        local ent = ents.Create( weapon.ClassName )
        if not IsValid( ent ) then
            return vkx_entspawner.print( "Failed to create %q for unknow reasons!", weapon.PrintName )
        end
        ent:SetPos( pos + Vector( 0, 0, 8 ) )
        ent:SetAngles( ang )
        ent:Spawn()

        return ent, "sents"
    end

    function vkx_entspawner.spawn_npc( key, pos, ang )
        local npc = cached_lists.NPC[key]
        if not npc then 
            return vkx_entspawner.print( "Try to spawn a NPC %q which doesn't exists!", key )
        end

        local ent = ents.Create( npc.Class )
        if not IsValid( ent ) then 
            return vkx_entspawner.print( "Failed to create %q for unknown reasons!", npc.Name ) 
        end
        if npc.Offset then pos = Vector( pos.x, pos.y, pos.z + npc.Offset ) end
        ent:SetPos( pos + Vector( 0, 0, 32 ) )
        ent:SetAngles( ang )
        if npc.Model then ent:SetModel( npc.Model ) end
        if npc.Health then 
            ent:SetMaxHealth( npc.Health )
            ent:SetHealth( npc.Health )
        end
        for k, v in pairs( npc.KeyValues or {} ) do
            ent:SetKeyValue( k, v )
        end
        for i, v in ipairs( npc.Weapons or {} ) do
            ent:Give( v )
        end
        ent:Spawn()
        if not npc.NoDrop then ent:DropToFloor() end

        return ent, "npcs"
    end

    function vkx_entspawner.can_spawn_safely( ent )
        if not IsValid( ent ) then return false end
        --if ent:IsInWorld() then return false end
        
        local pos = ent:GetPos()
        local min, max = ent:GetModelBounds()
        for i, v in ipairs( ents.FindInBox( pos + min, pos + max ) ) do
            if v == ent then continue end  --  skip self
            if entities_spawnlist and entities_spawnlist[v] then continue end  --  skip just spawned entities
            if vkx_entspawner.blocking_entity_blacklist[v:GetClass()] then continue end  --  skip blacklisted classes
            if v:GetBrushPlaneCount() > 0 or v:IsWeapon() then continue end  --  skip brushs & weapons

            local model = v:GetModel()
            if model and #model == 0 then continue end  --  skip non-model entities

            if not v:IsSolid() then continue end  --  skip non-solid entities

            --  prevent spawn
            vkx_entspawner.debug_print( "%q is blocking %q from spawning", tostring( v ), tostring( ent ) )    
            return false, v
        end

        return true
    end

    function vkx_entspawner.save_perma_spawners()
        --  map perma
        local spawners = {}
        for i, spawner in pairs( vkx_entspawner.spawners ) do
            if spawner.perma then
                --  remove useless variables
                local spawner = table.Copy( spawner )
                for i, v in ipairs( spawner.locations ) do
                    v.entities = nil
                end
                spawner.run_times = nil
                spawner.last_time = nil
                spawner.perma = nil
                spawner.id = nil

                spawners[#spawners + 1] = spawner
            end
        end

        --  folder(s) path
        local folder = vkx_entspawner.save_path:Split( "/" )
        table.remove( folder )
        folder = table.concat( folder, "/" )
        file.CreateDir( folder )

        --  save
        local json = util.TableToJSON( spawners, true )
        if not json then return vkx_entspawner.print( "Failed to save the perma spawners!" ) end
        file.Write( vkx_entspawner.save_path:format( game.GetMap() ), json )
    end

    function vkx_entspawner.load_perma_spawners()
        vkx_entspawner.spawners = {}

        --  load
        local content = file.Read( vkx_entspawner.save_path:format( game.GetMap() ) )
        if not content then return end
        
        local spawners = util.JSONToTable( content )
        if not spawners then return vkx_entspawner.print( "Failed to load the perma spawners!" ) end

        --  add spawners
        for i, spawner in pairs( spawners ) do
            spawner.perma = true
            spawner.id = nil
            spawner.run_times = nil
            vkx_entspawner.new_spawner( spawner, true )
        end
        vkx_entspawner.save_perma_spawners()

        vkx_entspawner.print( "Load %d spawners!", #spawners )
    end
    hook.Add( "InitPostEntity", "vkx_entspawner:spawner", vkx_entspawner.load_perma_spawners )
    concommand.Add( "vkx_entspawner_load_spawners", vkx_entspawner.load_perma_spawners )

    --[[ 
        @structure Location
            | description: Represents a position and an angle
            | params:
                pos: Vector
                ang: Angle
                entities: table[Entity] list of spawned entities for this location
        
        @structure EntityChance
            | description: Represents an entity class and his percent chance of getting it
            | params:
                key: string Entity Class Name
                percent: float Entity Chance, from 0 to 1, rounded to 2 decimals
        
        @structure EntitySpawner
            | description: Represents a spawner of entities
            | params:
                id: int Identifier of the spawner in the table `vkx_entspawner.spawners`
                locations: table[@Location] List of locations (position and angles) where entities will spawn
                entities: table[@EntityChance] List of spawnable entities 
                max: int Number of maximum entities per location
                delay: float Time needed between each spawn
                perma: bool? Is a Permanent Spawner, if so, the spawner will be saved
                oneshot: bool? Is a One-Shot Spawner, if so, the spawner will only run 'max' times and won't trigger again until map reload
                run_times: int? Number of times the spawner runned, used by 'oneshot' 
                last_time: float Last time the spawner was runned, use of CurTime
                radius: int Player Presence Radius, allow the spawner to run if a Player is in the radius 
                radius_disappear: bool? In addition to PPR, will disappear spawned entities if no Player is in the radius

        @function vkx_entspawner.new_spawner
            | description: Register a new spawner, network it and save it if 'perma' is true
            | params:
                spawner: @EntitySpawner Spawner to register
            | return: @EntitySpawner spawner
    ]]
    function vkx_entspawner.new_spawner( spawner, nosave )
        --  round percent
        for i, v in ipairs( spawner.entities ) do
            v.percent = math.Round( v.percent, 2 )
        end

        --  add 'entities' table to each location
        for i, v in ipairs( spawner.locations ) do
            v.entities = {}
        end

        --  add spawner
        spawner.last_time = spawner.last_time or CurTime()
        spawner.run_times = spawner.run_times or 0
        spawner.radius = spawner.radius or 0
        spawner.id = spawner.id or #vkx_entspawner.spawners + 1
        vkx_entspawner.spawners[spawner.id] = spawner

        --  save
        if not nosave and spawner.perma then
            vkx_entspawner.save_perma_spawners()
        end

        vkx_entspawner.safe_network_spawners()
        return spawner
    end

    function vkx_entspawner.delete_spawner( id )
        local spawner = vkx_entspawner.spawners[id]
        if not spawner then return end

        table.remove( vkx_entspawner.spawners, id )
        if spawner.perma then
            vkx_entspawner.save_perma_spawners()
        end
        vkx_entspawner.safe_network_spawners()
    end

    function vkx_entspawner.run_spawner( spawner, callback, err_callback )
        local spawned_count = 0
        for i, v in ipairs( spawner.locations ) do
            --  limit?
            v.entities = v.entities or {}
            for i, ent in ipairs( v.entities ) do
                if not IsValid( ent ) then
                    table.remove( v.entities, i )
                end
            end

            --  spawn
            if #v.entities < spawner.max then
                for i, chance in ipairs( spawner.entities ) do
                    if math.random() <= chance.percent then
                        --  spawn entity
                        local obj, type = vkx_entspawner.spawn_object( chance.key, v.pos, v.ang )
                        if IsValid( obj ) then
                            --  check is safe
                            local can_spawn, blocking_entity = vkx_entspawner.can_spawn_safely( obj )
                            if not can_spawn then
                                --  error callback
                                if err_callback then 
                                    err_callback( "cant_spawn", obj, blocking_entity ) 
                                end

                                --  remove
                                obj:Remove()
                                break
                            end

                            --  success callback
                            if callback then 
                                callback( obj, type ) 
                            end

                            --  register
                            v.entities[#v.entities + 1] = obj
                            spawned_count = spawned_count + 1
                        end

                        break
                    end
                end
            end
        end

        --  check for registered spawner and for new entities
        if vkx_entspawner.spawners[spawner.id] and spawned_count > 0 then
            --  increase run times
            spawner.run_times = ( spawner.run_times or 0 ) + 1
            
            --  delay next run
            spawner.last_time = CurTime()

            --  network
            if convar_network_run:GetBool() then
                timer.Simple( .1, function()  --  must be defered since entities are not instantanously created on clients
                    vkx_entspawner.network_run_spawner( spawner )
                end )
            end
        end

        return spawned_count
    end

    --  network spawners
    util.AddNetworkString( "vkx_entspawner:network" )
    util.AddNetworkString( "vkx_entspawner:run" )

    function vkx_entspawner.get_network_users()
        local users = {}

        for i, ply in ipairs( player.GetAll() ) do
            if convar_network_admin_only:GetBool() and not ply:IsSuperAdmin() then continue end
            
            users[#users + 1] = ply
        end

        return users
    end

    function vkx_entspawner.concat_players_names( players )
        local names = ""

        for i, ply in ipairs( players ) do
            names = names .. ( i == 1 and "" or ", " ) .. ply:GetName()
        end

        return players
    end
    
    function vkx_entspawner.network_spawners( ply )
        --  get users
        local users
        if not ply then
            users = vkx_entspawner.get_network_users()

            --  no one to send data
            if #users == 0 then 
                return 
            end
        else
            users = { ply }
        end

        --  send
        local spawners_count = table.Count( vkx_entspawner.spawners )
        net.Start( "vkx_entspawner:network" )
            net.WriteUInt( spawners_count, vkx_entspawner.NET_SPAWNERS_BITS )
            for i, spawner in pairs( vkx_entspawner.spawners ) do
                net.WriteUInt( spawner.id, vkx_entspawner.NET_SPAWNER_ID_BITS )
                net.WriteBool( spawner.perma )
                net.WriteBool( spawner.oneshot )
                
                --  locations
                net.WriteUInt( #spawner.locations, vkx_entspawner.NET_SPAWNER_LOCATIONS_BITS )
                for i, v in ipairs( spawner.locations ) do
                    net.WriteVector( v.pos )
                    net.WriteAngle( v.ang )
                end

                --  entities chance
                net.WriteUInt( #spawner.entities, vkx_entspawner.NET_SPAWNER_ENTS_CHANCE_BITS )
                for i, v in ipairs( spawner.entities ) do
                    net.WriteString( v.key )
                    net.WriteFloat( v.percent )
                end

                net.WriteUInt( spawner.max, vkx_entspawner.NET_SPAWNER_MAX_ENTITIES_BITS )
                net.WriteUInt( spawner.delay, vkx_entspawner.NET_SPAWNER_DELAY_BITS )
                net.WriteUInt( spawner.radius, vkx_entspawner.NET_SPAWNER_RADIUS_BITS )
                net.WriteBool( spawner.radius_disappear )
                net.WriteFloat( spawner.last_time )
                net.WriteUInt( spawner.run_times, vkx_entspawner.NET_SPAWNER_RUN_TIMES_BITS )
            end
        net.Send( users )

        --  debug
        if vkx_entspawner.is_debug() then
            vkx_entspawner.debug_print( "sent %d spawners to %s", spawners_count, vkx_entspawner.concat_players_names( users ) )
        end
    end

    function vkx_entspawner.safe_network_spawners( ply )
        timer.Create( "vkx_entspawner:network" .. ( IsValid( ply ) and ply:UniqueID() or "" ), .1, 1, function()
            vkx_entspawner.network_spawners( ply )
        end )
    end

    net.Receive( "vkx_entspawner:network", function( len, ply )
        if convar_network_admin_only:GetBool() and not ply:IsSuperAdmin() then return end

        vkx_entspawner.network_spawners( ply )
    end )

    function vkx_entspawner.network_run_spawner( spawner )
        --  get users
        local users = vkx_entspawner.get_network_users()
        if #users == 0 then 
            return 
        end

        --  send
        net.Start( "vkx_entspawner:run" )
            net.WriteUInt( spawner.id, vkx_entspawner.NET_SPAWNER_ID_BITS )
            net.WriteFloat( spawner.last_time )
            net.WriteUInt( spawner.run_times, vkx_entspawner.NET_SPAWNER_RUN_TIMES_BITS )

            --  send active entities
            for i, v in ipairs( spawner.locations ) do
                net.WriteUInt( #v.entities, vkx_entspawner.NET_SPAWNER_MAX_ENTITIES_BITS )

                for i, ent in ipairs( v.entities ) do
                    if IsValid( ent ) then
                        net.WriteEntity( ent )
                    end
                end
            end
        net.Send( users )
    end

    --  spawner time
    local fake_cleanup_id = -1
    timer.Create( "vkx_entspawner:spawner", 1, 0, function()
        if player.GetCount() <= 0 then return end

        for i, spawner in pairs( vkx_entspawner.spawners ) do
            --  check delay
            if CurTime() - spawner.last_time < spawner.delay then continue end

            --  call hook
            local should_run = hook.Run( "vkx_entspawner:should_spawner_run", spawner )
            if not ( should_run == false ) then
                --  run spawner
                vkx_entspawner.run_spawner( spawner, function( obj, type )
                    local list = cleanup.GetList()
                    list[fake_cleanup_id] = list[fake_cleanup_id] or {}
                    list[fake_cleanup_id][type] = list[fake_cleanup_id][type] or {}
                    list[fake_cleanup_id][type][#list[fake_cleanup_id][type] + 1] = obj
                end )
            end
        end
    end )

    hook.Add( "vkx_entspawner:should_spawner_run", "vkx_entspawner:one_shot", function( spawner )
        --  one-shot
        if spawner.oneshot and ( spawner.run_times or 0 ) >= spawner.max then 
            return false 
        end
    end )

    hook.Add( "vkx_entspawner:should_spawner_run", "vkx_entspawner:player_radius", function( spawner )
        --  player presence radius
        if ( spawner.radius or 0 ) > 0 then
            local has_someone_within = false
            for i, ply in ipairs( player.GetAll() ) do
                if ply:GetPos():Distance( vkx_entspawner.get_spawner_center( spawner ) ) <= spawner.radius then
                    has_someone_within = true
                    break
                end
            end

            if not has_someone_within then
                --  player presence disappear
                if spawner.radius_disappear then
                    for i, v in ipairs( spawner.locations ) do
                        for i, ent in ipairs( v.entities ) do
                            if IsValid( ent ) then
                                ent:Remove()
                            end
                        end
                        v.entities = {}
                    end
                end

                return false
            end
        end
    end )

    --  notification
    util.AddNetworkString( "vkx_entspawner:notify" )
    function vkx_entspawner.notify( ply, msg, type )
        net.Start( "vkx_entspawner:notify" )
            net.WriteString( msg )
            net.WriteUInt( type, 3 )
        net.Send( ply )
    end
end



--  shape list
list.Set( "vkx_entspawner_shapes", "None", {
    z_order = 0,
    compute = function( tool )
        return { 
            {
                pos = Vector(), 
                ang = Angle(),
            },
        } 
    end,
} )
list.Set( "vkx_entspawner_shapes", "Circle", {
    z_order = 1,
    convars = {
        circle_number = {
            name = "Number",
            default = "3",
            template = {
                type = "Int",
                options = {
                    min = 1,
                    max = 64,
                },
            },
        },
        circle_radius = {
            name = "Radius",
            default = "64",
            template = {
                type = "Float",
                options = {
                    min = 32,
                    max = 1000,
                    --decimals = 2,
                },
            },
        },
        offset_angle = {
            name = "Offset Angle",
            default = "0",
            template = {
                type = "Int",
                options = {
                    min = 0,
                    max = 360,
                },
            },
        },
    },
    compute = function( tool )
        local positions = {}
        local radius, number = tool:GetClientNumber( "circle_radius", 64 ), tool:GetClientNumber( "circle_number", 1 )

        for a = 1, 360, 360 / number do
            local ang = math.rad( a )
            positions[#positions + 1] = {
                pos = Vector( math.cos( ang ), math.sin( ang ), 0 ) * radius,
                ang = Angle( 0, a + tool:GetClientNumber( "offset_angle", 0 ), 0 ),
            }
        end

        return positions
    end,
} )
list.Set( "vkx_entspawner_shapes", "Square", {
    z_order = 2,
    convars = {
        square_offset = {
            z_order = 0,
            name = "Offset",
            default = "64",
            template = {
                type = "Int",
                options = {
                    min = 32,
                    max = 1000,
                },
            },
        },
        square_width = {
            z_order = 1,
            name = "Width",
            default = "3",
            template = {
                type = "Int",
                options = {
                    min = 1,
                    max = 64,
                },
            },
        },
        square_length = {
            z_order = 2,
            name = "Length",
            default = "3",
            template = {
                type = "Int",
                options = {
                    min = 1,
                    max = 64,
                },
            },
        },
    },
    compute = function( tool )
        local positions = {}
        local offset = tool:GetClientNumber( "square_offset", 64 )

        local size_x, size_y = tool:GetClientNumber( "square_width", 3 ), tool:GetClientNumber( "square_length", 3 )
        local n, n_max = 0, size_x * size_y
        local center_offset = Vector( ( size_y + 1 ) * offset, ( size_x + 1 ) * offset, 0 ) / 2
        for y = 1, size_x do
            for x = 1, size_y do
                if n >= n_max then break end
                positions[#positions + 1] = {
                    pos = Vector( x * offset, y * offset, 0 ) - center_offset,
                    ang = Angle(),
                }
                n = n + 1
            end
        end

        return positions
    end,
} )
list.Set( "vkx_entspawner_shapes", "Random", {
    z_order = 3,
    convars = {
        random_number = {
            z_order = 0,
            name = "Number",
            default = "3",
            template = {
                type = "Int",
                options = {
                    min = 1,
                    max = 64,
                },
            },
        },
        random_radius = {
            z_order = 1,
            name = "Radius",
            default = "64",
            template = {
                type = "Float",
                options = {
                    min = 32,
                    max = 1000,
                    --decimals = 2,
                },
            },
        },
        random_x_ratio = {
            z_order = 2,
            name = "X Ratio",
            default = "1",
            template = {
                type = "Float",
                options = {
                    min = 0,
                    max = 1,
                    --decimals = 2,
                },
            },
        },
        random_y_ratio = {
            z_order = 3,
            name = "Y Ratio",
            default = "1",
            template = {
                type = "Float",
                options = {
                    min = 0,
                    max = 1,
                    --decimals = 2,
                },
            },
        },
    },
    compute = function( tool )
        local positions = {}
        local radius, number = tool:GetClientNumber( "random_radius", 64 ), tool:GetClientNumber( "random_number", 1 )
        local x_ratio, y_ratio = tool:GetClientNumber( "random_x_ratio", 1 ), tool:GetClientNumber( "random_y_ratio", 1 )

        for a = 1, 360, 360 / number do
            local ang, r = math.rad( a ), math.random( radius )
            positions[#positions + 1] = {
                pos = Vector( math.cos( ang ) * y_ratio * r, math.sin( ang ) * x_ratio * r, 0 ),
                ang = Angle( 0, math.random( 360 ), 0 ),
            }
        end

        return positions
    end,
} )