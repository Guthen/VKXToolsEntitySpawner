# v2.3.0: Custom Preset System
## Users
+ **feature:** a Custom Preset System allowing to save the list of selected entities
+ **feature:** added an offset angle parameter to `Circle` shape
+ **fix:** using the gravity gun shortcut still render the preview 
+ **fix:** error while using the tool in a instant spawn mode 

## Developpers
+ **update:** refactored the preview renderer, now, only one CSEntity is used to draw all preview locations. Functions about 'GhostEntity' have been changed, see source code.
+ **update:** `vkx_entspawner.new_spawner` return now an `@EntitySpawner` instead of the spawner's ID
+ **update:** `@EntityChance.percent` has been remapped from 0-100 to 0-1 (2 decimals) 
+ **update:** Shape's `convars` is now a table of table using a specific structure instead of a table of string containing the value (see end of the autorun file for examples). This is intended for giving enough information to the Preset System 

# v2.3.1: Fix Gredwitch's Emplacements compatibility
# v2.3.2: Add `physgun_beam` & `predicted_viewmodel` to blacklist
# v2.3.3: Fix Entities Spawning for 3rd Party Addons
## Users
+ **fix:** most of compatibility by spawning entities from **3rd Party Addons** is fixed including ─ but not limited to ─ **Gredwitch's Emplacements** & **WAC**

## Developpers
+ **new:** added server-side function `vkx_entspawner.spawn_sent` which is used to spawn Scripted Entities instead of using `vkx_entspawner.spawn_entity` 
# v2.4.0: Copy hovering Spawner Settings
## Users
+ **new:** added ability to copy a spawner settings by pressing **Reload** with the tool while hovering the cursor on the spawner
## Developpers
+ **fix:** reduce amount of data sent over network when a player request the creation of a spawner & while sending spawners to a player
# v2.4.1: Saving w/ pretty JSON
# v2.4.2: Fix Networking issues upon Spawner Creation
# v2.4.3: Single Player support
# v2.4.4: Copying Spawners no longer freezes game & Single Player Copy support 