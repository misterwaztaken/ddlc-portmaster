#!/bin/bash
# DDLC Launch Script

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

pm_message "Control folder: $controlfolder"

# --- Configuration Variables ---
GAMEDIR="./DDLC_PORT"
RUNTIME="renpy_8.1.3.aarch64"
PORTEXEC="renpy/lib/py3-linux-aarch64/startRENPY"

# Change to the script's directory first
cd "$(dirname "$0")"

# Change into the game directory
if [ ! -d "$GAMEDIR" ]; then
    pm_message "FATAL ERROR: Game data folder '$GAMEDIR' not found."
    sleep 5
    exit 1
fi
cd "$GAMEDIR" || {
    pm_message "FATAL ERROR: Failed to change directory to '$GAMEDIR'."
    sleep 5
    exit 1
}

# Correct GAMEDIR to be absolute after the initial cd for mounting stability
GAMEDIR="$(pwd)"

# -----------------------------------------------
# 2. RUNTIME & FILE SYSTEM SETUP
# -----------------------------------------------

# Savedata setup
mkdir -p "$GAMEDIR/conf"
export XDG_DATA_HOME="$GAMEDIR/conf"
bind_directories ~/.renpy/ "$GAMEDIR/conf/"

renpydir="$GAMEDIR/renpy/"
$ESUDO mkdir -p "$renpydir"
renpy_runtime="$controlfolder/libs/${RUNTIME}.squashfs"

# Check for runtime availability (simplified)
if [ ! -f "$renpy_runtime" ]; then
    pm_message "FATAL ERROR: Runtime $RUNTIME.squashfs not found."
    sleep 5
    exit 1
fi

# Mounting Renpy
pm_message "Attempting to mount runtime: $renpy_runtime to $renpydir"
$ESUDO umount "$renpydir" || true
$ESUDO mount "$renpy_runtime" "$renpydir" || {
    pm_message "FATAL ERROR: Failed to mount runtime."
    sleep 5
    exit 1
}

# -----------------------------------------------
# 3. EXPORTS AND LAUNCH
# -----------------------------------------------

export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"
export LD_LIBRARY_PATH="$GAMEDIR/libs:$LD_LIBRARY_PATH"
export PYTHONHOME="$GAMEDIR/renpy/"
export PYTHONPATH="$GAMEDIR/renpy/lib/python3.9"

# If using gl4es (CRITICAL for display issues)
if [ -f "${controlfolder}/libgl_${CFW_NAME}.txt" ]; then
    source "${controlfolder}/libgl_${CFW_NAME}.txt"
else
    source "${controlfolder}/libgl_default.txt"
fi

if [[ "$LIBGL_FB" != "" ]]; then
    export SDL_VIDEO_GL_DRIVER="$GAMEDIR/gl4es/libGL.so.1"
    export SDL_VIDEO_EGL_DRIVER="$GAMEDIR/gl4es/libEGL.so.1"
fi

# --- Resolution and Aspect Ratio Fixes for R36S (4:3) ---
export SDL_VIDEO_WIDTH="640"
export SDL_VIDEO_HEIGHT="480"
export GL4ES_ASPECT_RATIO=1 # Ensures proper 4:3 scaling

# Log output
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

# Launch the game
RENPY_EXEC="$GAMEDIR/$PORTEXEC"
pm_message "Launching $RENPY_EXEC with game data at $GAMEDIR/gamedata..."

# --- REMOVED pm_platform_helper as it causes an error and is not strictly needed ---

# --- GPTOKEYB (Controls) Launch ---
# We use 'startRENPY' as the target name and add a delay for stability.
$GPTOKEYB "startRENPY" -f startRENPY.gptk &
sleep 3 # Give the control mapper time to initialize

"$RENPY_EXEC" "$GAMEDIR/gamedata" # Game Execution

# -----------------------------------------------
# 4. CLEANUP AND EXIT
# -----------------------------------------------

if [[ "$PM_CAN_MOUNT" != "N" ]]; then
    pm_message "Unmounting runtime..."
    $ESUDO umount "$renpydir"
fi

pm_finish
