#!/bin/bash

# ===============================================
# 1. PORTMASTER SETUP AND ENVIRONMENT
# ===============================================

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

# Locate the PortMaster control folder
if [ -d "/opt/system/Tools/PortMaster/" ]; then
    controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
    controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
    controlfolder="$XDG_DATA_HOME/PortMaster"
else
    controlfolder="/roms/ports/PortMaster"
fi

# Source necessary PortMaster variables and functions
source "$controlfolder/control.txt"
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls

# --- Configuration Variables ---
# IMPORTANT: Adjust these paths to match your game structure.
PORTEXEC="renpy/startRENPY"
GAMEDIR="$(dirname "$0")"
RUNTIME="renpy_8.1.3" # Match the required Ren'Py runtime version

cd "$GAMEDIR"

# -----------------------------------------------
# 2. PATCHING LOGIC (Adapted for PortMaster)
# -----------------------------------------------

# Define patching variables inside the function for scope, or globally if needed
TARGET_RPYC="temp/script-poemgame.rpyc"
DECOMPILED_FILE_NAME="script-poemgame.rpy"
TARGET_RPY="temp/$DECOMPILED_FILE_NAME" # Store RPY directly in temp for easier repack
ORIGINAL_RPA_PATH="./rpa-files-test/scripts.rpa"
FINAL_RPA_DEST="./gamedata/game/scripts.rpa"
FIRST_RUN_FLAG="./gamedata/.patch_complete"

# Define the replacement snippet (using an exported variable is safer for SED)
export PATCH="with renpy.file('poemwords.txt') as wordfile:
        for line in wordfile:
            
            line = line.decode('utf-8')

            line = line.strip()

            if line == '' or line[0] == '#': continue
        
        
            x = line.split(',') 
            full_wordlist.append(PoemWord(x[0], float(x[1]), float(x[2]), float(x[3])))"

# NOTE: The patch function now places the RPY directly into the 'temp' folder root.
patch() {
    pm_message "First run detected. Starting RPA patching process."

    # 1. Clean up unnecessary Windows files (Good practice for porting)
    pm_message "Purging Windows executable and library files..."
    rm -rf gamedata/*.exe gamedata/lib/*/*.dll gamedata/lib/*/*.exe

    # 2. Extract the necessary RPA file
    pm_message "Extracting scripts.rpa to temp dir..."
    mkdir -p temp
    python3 firstrun_helpers/rpatool -o temp -x "$ORIGINAL_RPA_PATH" || {
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
    # unrpyc usually outputs the .rpy next to the .rpyc (inside 'temp')
    python3 firstrun_helpers/unrpyc.py "$TARGET_RPYC"

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
    
    # Use sed to delete and insert the new code
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
    
    # Delete the old, incorrect compiled file
    rm -f "$TARGET_RPYC"
    
    # 8. Create Backup and Repack
    BACKUP_RPA_FILE="${ORIGINAL_RPA_PATH}.bak_$(date +%Y%m%d%H%M%S)"
    cp "$ORIGINAL_RPA_PATH" "$BACKUP_RPA_FILE"
    pm_message "Original RPA backed up."
    
    # Create the new archive directly into the final game directory, compressing contents of 'temp'
    python3 firstrun_helpers/rpatool -c "$FINAL_RPA_DEST" temp || {
        pm_message "Error: Repacking failed. Aborting."
        sleep 5
        exit 1
    }

    # 9. Cleanup
    pm_message "Cleaning up temporary files..."
    rm -rf temp 
    
    # 10. Set flag to prevent future patching
    touch "$FIRST_RUN_FLAG"
    pm_message "Patching and setup complete. Game ready to launch."
}

# -----------------------------------------------
# 3. RUNTIME & FILE SYSTEM SETUP (From Example)
# -----------------------------------------------

# Savedata setup
mkdir -p "$GAMEDIR/conf"
export XDG_DATA_HOME="$GAMEDIR/conf"
bind_directories ~/.renpy/ "$GAMEDIR/conf/"

renpydir="$GAMEDIR/renpy/"
$ESUDO mkdir -p "$renpydir"
renpy_runtime="$controlfolder/libs/${RUNTIME}.squashfs"

# Check for runtime availability
if [ ! -f "$renpy_runtime" ]; then
    pm_message "Downloading Ren'Py runtime..."
    if [ ! -f "$controlfolder/harbourmaster" ]; then
        pm_message "This port requires the latest PortMaster to run, please go to https://portmaster.games/ for more info."
        sleep 5
        exit 1
    fi
    $ESUDO "$controlfolder/harbourmaster" --quiet --no-check runtime_check "${RUNTIME}.squashfs"
fi

# Mounting Renpy
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

# Exports
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"
export LD_LIBRARY_PATH="$GAMEDIR/libs:$LD_LIBRARY_PATH"
export PYTHONHOME="$GAMEDIR/renpy/"
export PYTHONPATH="$GAMEDIR/renpy/lib/python3.9"

# If using gl4es (Required for many handhelds)
if [ -f "${controlfolder}/libgl_${CFW_NAME}.txt" ]; then
    source "${controlfolder}/libgl_${CFW_NAME}.txt"
else
    source "${controlfolder}/libgl_default.txt"
fi

# Set GL environment variables if needed
if [[ "$LIBGL_FB" != "" ]]; then
    export SDL_VIDEO_GL_DRIVER="$GAMEDIR/gl4es/libGL.so.1"
    export SDL_VIDEO_EGL_DRIVER="$GAMEDIR/gl4es/libEGL.so.1"
fi

# Log output (optional but good for debugging)
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

# Launch the game with GpToKeyb for input mapping
pm_platform_helper "$GAMEDIR/renpy/lib/py3-linux-aarch64/startRENPY"
$GPTOKEYB "startRENPY" -c "$PORTEXEC" &
"$PORTEXEC" "$GAMEDIR/game"

# -----------------------------------------------
# 5. CLEANUP AND EXIT
# -----------------------------------------------

if [[ "$PM_CAN_MOUNT" != "N" ]]; then
    pm_message "Unmounting runtime..."
    $ESUDO umount "$renpydir"
fi

pm_finish