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
