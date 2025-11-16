#!/bin/bash

# ===============================================
# 1. PORTMASTER SETUP AND ENVIRONMENT
# ===============================================

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

# Locate the PortMaster control folder
if [ -d "/opt/system/Tools/PortMaster/" ]; then
    controlfolder="/opt/system/Tools/PortMaster"
# ... [Other PortMaster controlfolder logic remains here] ...
else
    controlfolder="/roms/ports/PortMaster"
fi

# Source necessary PortMaster variables and functions
source "$controlfolder/control.txt"
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls

# Set current working directory to the script's location
cd "$(dirname "$0")"

# --- Configuration Variables ---
# The name of the game data folder (e.g., where the 'gamedata' folder lives)
GAMEDIR="./DDLC" 
RUNTIME="renpy_8.1.3" 
# The actual script/executable that launches the Ren'Py engine, located next to launch.sh
GAMELAUNCHER="./DDLC.sh" 

# -----------------------------------------------
# 2. PATCHING LOGIC (Using $GAMEDIR Prefix)
# -----------------------------------------------

# Define patching variables with the $GAMEDIR prefix
TARGET_RPYC="$GAMEDIR/temp/script-poemgame.rpyc"
DECOMPILED_FILE_NAME="script-poemgame.rpy"
TARGET_RPY="$GAMEDIR/temp/$DECOMPILED_FILE_NAME"
ORIGINAL_RPA_PATH="$GAMEDIR/rpa-files-test/scripts.rpa"
FINAL_RPA_DEST="$GAMEDIR/gamedata/game/scripts.rpa"
FIRST_RUN_FLAG="$GAMEDIR/gamedata/.patch_complete"
HELPER_PATH="$GAMEDIR/firstrun_helpers"

# Define the replacement snippet (exported for SED)
export PATCH="with renpy.file('poemwords.txt') as wordfile:
        for line in wordfile:
            
            line = line.decode('utf-8')

            line = line.strip()

            if line == '' or line[0] == '#': continue
        
        
            x = line.split(',') 
            full_wordlist.append(PoemWord(x[0], float(x[1]), float(x[2]), float(x[3])))"

patch() {
    pm_message "First run detected. Starting RPA patching process."

    # 1. Clean up unnecessary Windows files
    pm_message "Purging Windows executable and library files..."
    rm -rf "$GAMEDIR/gamedata/"*.exe "$GAMEDIR/gamedata/lib/"*/*.dll "$GAMEDIR/gamedata/lib/"*/*.exe

    # 2. Extract the necessary RPA file
    pm_message "Extracting scripts.rpa to temp dir..."
    mkdir -p "$GAMEDIR/temp"
    python3 "$HELPER_PATH/rpatool" -o "$GAMEDIR/temp" -x "$ORIGINAL_RPA_PATH" || {
        pm_message "Error: rpatool extraction failed."
        sleep 5
        exit 1
    }

    # 3. Check for the target RPYC file
    if [ ! -f "$TARGET_RPYC" ]; then
        echo "Error: Could not find $TARGET_RPYC"
        sleep 5
        exit 1
    fi

    # 4. Decompile the RPYC file
    pm_message "Decompiling $TARGET_RPYC..."
    python3 "$HELPER_PATH/unrpyc.py" "$TARGET_RPYC"

    # 5. Check for the decompiled RPY file
    if [ ! -f "$TARGET_RPY" ]; then
        echo "Error: Could not find decompiled file $TARGET_RPY"
        sleep 5
        exit 1
    fi
    
    # 6. Apply the SED Patch
    pm_message "Applying sed patch to $TARGET_RPY..."
    
    local START_MARKER="full_wordlist = \[]"
    local END_MARKER="seen_eyes_this_chapter = False"
    
    sed -i.bak -e "/$START_MARKER/,/$END_MARKER/{
        /$START_MARKER/!{
            /$END_MARKER/!d
        }
    }" -e "/$END_MARKER/i\\
$PATCH
" "$TARGET_RPY"

    if [ $? -ne 0 ]; then
        echo "Error: sed command failed during patching. Aborting."
        sleep 5
        exit 1
    fi
    pm_message "Patch applied successfully. Backup: $TARGET_RPY.bak."
    
    # 7. Prepare for Repackaging
    pm_message "Deleting old RPYC and repacking..."
    
    rm -f "$TARGET_RPYC"
    
    # 8. Create Backup and Repack
    BACKUP_RPA_FILE="${ORIGINAL_RPA_PATH}.bak_$(date +%Y%m%d%H%M%S)"
    cp "$ORIGINAL_RPA_PATH" "$BACKUP_RPA_FILE"
    
    pm_message "Compressing files into new RPA at $FINAL_RPA_DEST..."
    python3 "$HELPER_PATH/rpatool" -c "$FINAL_RPA_DEST" "$GAMEDIR/temp" || {
        pm_message "Error: Repacking failed. Aborting."
        sleep 5
        exit 1
    }

    # 9. Cleanup
    pm_message "Cleaning up temporary files..."
    rm -rf "$GAMEDIR/temp"
    
    # 10. Set flag to prevent future patching
    touch "$FIRST_RUN_FLAG"
    pm_message "Patching and setup complete. Game ready to launch."
}

# -----------------------------------------------
# 3. RUNTIME & FILE SYSTEM SETUP
# -----------------------------------------------

# Savedata setup needs the prefix
mkdir -p "$GAMEDIR/conf"
export XDG_DATA_HOME="$GAMEDIR/conf"
bind_directories ~/.renpy/ "$GAMEDIR/conf/"

# RenPy runtime paths need the prefix
renpydir="$GAMEDIR/renpy/"
$ESUDO mkdir -p "$renpydir"
renpy_runtime="$controlfolder/libs/${RUNTIME}.squashfs"

# ... [Runtime download and mounting logic remains here] ...

pm_message "Mounting Ren'Py runtime..."
$ESUDO umount "$renpydir" || true
$ESUDO mount "$renpy_runtime" "$renpydir"

# Run the patch if the flag file doesn't exist
if [ ! -f "$FIRST_RUN_FLAG" ]; then
    patch
fi

# -----------------------------------------------
# 4. EXPORTS AND LAUNCH
# -----------------------------------------------

# Exports must still use the correct game paths
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"
export LD_LIBRARY_PATH="$GAMEDIR/libs:$LD_LIBRARY_PATH"
export PYTHONHOME="$GAMEDIR/renpy/"
export PYTHONPATH="$GAMEDIR/renpy/lib/python3.9"

# If using gl4es (logic remains the same)
if [ -f "${controlfolder}/libgl_${CFW_NAME}.txt" ]; then
    source "${controlfolder}/libgl_${CFW_NAME}.txt"
else
    source "${controlfolder}/libgl_default.txt"
fi

if [[ "$LIBGL_FB" != "" ]]; then
    export SDL_VIDEO_GL_DRIVER="$GAMEDIR/gl4es/libGL.so.1"
    export SDL_VIDEO_EGL_DRIVER="$GAMEDIR/gl4es/libEGL.so.1"
fi

# Log output
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

# Launch the game: 
# The launcher script/binary is executed from the current directory, 
# and the full path to the game's data folder ($GAMEDIR) is passed as the argument.
pm_message "Launching $GAMELAUNCHER with game data at $GAMEDIR..."
pm_platform_helper "$GAMEDIR/renpy/lib/py3-linux-aarch64/startRENPY"
$GPTOKEYB "startRENPY" -c "$GAMELAUNCHER" &
"$GAMELAUNCHER" "$GAMEDIR/game" 

# -----------------------------------------------
# 5. CLEANUP AND EXIT
# -----------------------------------------------

if [[ "$PM_CAN_MOUNT" != "N" ]]; then
    pm_message "Unmounting runtime..."
    $ESUDO umount "$renpydir"
fi

pm_finish
