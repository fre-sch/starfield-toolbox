# Starfield Toolbox

A collection of scripts to help modding Starfield.

## Scripts

### xedit-scripts/Create new part.pas

Copy a full ship part hierachy, can start at COBJ, FLST, GBFM.

COBJ and FLST will be copied as overrides, while everything beyond GBFM is copied
as new.

TODO: Sometimes the script will fail when starting with COBJ/FLST. It appears, in
some cases, the FormID house-keeping gets jumbled. In that case, start the script
at the GBFMs and manually copy the COBJ and FLST as overrides.

NOTE: The script cannot copy anything with REFL data, that is a limitation of
xedit. In these cases, there will be NULL linked CELL children, remove these.


### xedit-scripts/BlenderJSON-Export.pas

Export CELL and other types to a JSON file.

Script can be applied to a CELL, REFR, MSTT, STAT, or STMP.


### xedit-scripts/BlenderJSON-Import.pas

Companion to BlenderJSON-Export, this reimports the JSON data. This script only
updates records exported previously. It cannot be used to create new part records.

JSON as exported by BlenderJSON-Export.pas contains the FormIDs of exported records.
BlenderJSON-Import.pas uses this data to update only records contained in the JSON.
Because of this, it doesn't need any specific record to be selected to apply it.


### blender-scripts/starfield_json_io.py

Companion to the xedit-scripts, this Blender Addon enables import/export of the
JSON data. Much like the xedit BlenderJSON-Import.pas script, this addon is not
made to create new data, only import modify and save.

In addition to the import/export functionality, it adds a gizmo to help visualize
the ship part snaps, and an object property panel to show the json meta information
contained in the JSON.


### Installation

Copy the *.pas files into your xedit/Edit Scripts directory or use symlinks.
Or use symlinks (REMEMBER TO CHANGE THE PATHS TO YOUR DOWNLOADS AND XEDIT FOLDER):

```shell
> New-Item -ItemType SymbolicLink -Target "starfield-toolbox\xedit-scripts\BlenderJSON-Export.pas" -Path "xedit\Edit Scripts\BlenderJSON-Export.pas"
> New-Item -ItemType SymbolicLink -Target "starfield-toolbox\xedit-scripts\BlenderJSON-Import.pas" -Path "xedit\Edit Scripts\BlenderJSON-Import.pas"
> New-Item -ItemType SymbolicLink -Target "starfield-toolbox\xedit-scripts\Create new part.pas" -Path "xedit\Edit Scripts\Create new part.pas"
```

In Blender add starfield_json_io.py as addon.


## Plans

* Fix blender export, fix xedit import
* Create xedit JSON import script that can completely create new parts
* Enable loading NIFs in Blender, early attempts show this is generally possible
  but is unusable due to the loading times of the starfield NIF importer.
