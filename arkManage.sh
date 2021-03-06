#!/bin/bash

# where is the config located
source /home/ark/scripts/config.conf

UPDATES_EXECUTABLE=0
UPDATES_WORKSHOP=0
STEAM_APPCHACHE=STEAM_DIR/appcache

# change to warnign time in minutes
SHUTDOWN_TIME_UPDATES=15

parseConfig() {
    RCON_PW=$(cat $CONFIG | grep $CFG_RCON_PW | cut -d'=' -f2)
    RCON_PORT=$(cat $CONFIG | grep $CFG_RCON_PORT| cut -d'=' -f2)
}

# params:
# 1: time
# 2: (m|s): minutes or seconds
# 3: message
msgServer() {
    local timeType="seconds"
    if [ "$2" = "m" ]; then
        timeType="minutes"
    fi

    local Message="$3"
    if [ -z "$Message" ]; then
        Message="No reason given"
    fi

    $MCRCON -s -H $RCON_HOST -P $RCON_PORT -p $RCON_PW "Broadcast Server shutting down in $1 $timeType. Reason: $Message"
    echo -e "Server shutting down in $1 $timeType. Reason: $Message"
}

countDown() {
    local Message=$1
    msgServer 60 "s" "$Message"
    # echo -e "Shut down in 60 seconds."
    sleep 30s
    msgServer 30 "s" "$Message"
    # echo -e "Shut down in 30 seconds."
    sleep 15s
    local timer=15
    while [ $timer -gt 0 ]; do
        msgServer $timer "s" "$Message"
        #echo -e "Shut down in $timer."
        sleep 1s
        let timer-=1
    done

    # stop server
    $MCRCON -s -H $RCON_HOST -P $RCON_PORT -p $RCON_PW $RCON_STOP
}

# taken from https://github.com/Zendrex/ARK-Linux-Server-Script
waitBackgroundTask () {
    PROC_ID=$1

    echo -ne " "
    while :; do
        if kill -0 $PROC_ID 2>/dev/null; then
            echo -ne "."
        else
            break
        fi
        sleep 0.5s
    done

    echo -e
}

# taken from https://github.com/Zendrex/ARK-Linux-Server-Script
parseSteamAcf () {
    local path=$1
    if [ -z $path ]; then
        return
    fi

    local splitPos=`expr index "$path" .`
    local newPath=""
    local searchName="\"$path\""
    if [ $splitPos -gt 0 ]; then
        newPath=${path:$splitPos}
        searchName=${path:0:$splitPos-1}
        searchName="\"$searchName\""
    fi

    local count=0
    while read name val; do
        if [ -z $name ]; then
            continue
        fi

        if [ $name == $searchName ] && [ $count -lt 2 ]; then
            if [ -z $newPath ]; then
                local length=${#val}
                echo ${val:1:$length-2}
            else
                parseSteamAcf $newPath
            fi
            return
        elif [ $name == "{" ]; then
            count=$((count+1))
        elif [ $name == "}" ]; then
            count=$((count-1))
            if [ $count -eq 0 ]; then
                break
            fi
        fi
    done

    echo "-1"
}

start () {
    if screen -list | grep -q $SCREEN; then
        echo -e "Screen session is already running. Checking if there is a server process ..."

        if [ $(ps ux | grep -o "$EXECUTABLE" | wc -l) -gt 2 ]; then # ps gives 3 results
            echo -e "Server is already running. Nothing to do here ..."
            return
        else
            echo -e "Starting server in screen session $SCREEN."
            screen -S $SCREEN -X stuff "$EXECUTABLE $LAUNCH_PARAMS $(printf '\r')"
        fi
    else
        echo -e "Starting the server in the new screen session $SCREEN"
        echo -e "Params:"
        echo -e "$LAUNCH_PARAMS"
        screen -d -m -S $SCREEN $EXECUTABLE $LAUNCH_PARAMS
    fi
}

stop () {
    if [ -z "$RCON_PW" -o -z "$RCON_PORT" ]; then
        parseConfig
    fi

    if [ -z "$RCON_PW" -o -z "$RCON_PORT" ]; then
        echo "Error parsing config or no RCON values provided"
        exit 1
    fi

    if ! lsof -i | grep -q "$RCON_PORT (LISTEN)"; then
        echo -e "Server is not running on RCON port $RCON_PORT."
        echo -e "Can't shut it down!"
        return
    fi

    local Time=$1
    local Message="${@:2}"

    if [ -z "$Time" ]; then
        Time=1
    fi

    if ! [[ "$Time" =~ ^[0-9]+$ ]]; then
        echo -e "No valid Time given, using 1 minute"
        Time=1
        Message="$@"
    fi

    #echo -e "Stopping server in $Time minute(s)."

    while [ $Time -ge $WARNING_INTERVALL ]; do
        msgServer $Time "m" "$Message"

        if [ $(($Time-$WARNING_INTERVALL)) -ge 5 ]
        then
            let Time-=$WARNING_INTERVALL
            sleep $(($WARNING_INTERVALL*60))
        else
            # wait until there are 5 minutes left
            sleep $((($Time-5)*60))
            Time=5
        fi
    done

    if [ $Time -gt 1 ]; then
        msgServer $Time "m" "$Message"
        # wait until there is 1 minute left
        sleep $((($Time-1)*60))
        Time=1
    fi

    countDown "$Message"
}

update () {
    if screen -list | grep -q $SCREEN; then
        echo -e "There is already a screen session running."
        echo -e "Aborting ..."
        echo -e
        exit 1
    fi

    $STEAM_CMD +runscript "$STEAMCMD_UPDATE"
    echo -e; echo -e;

    if [ -z "$STEAM_WORKSHOP_APPID" -o -z "$STEAM_WORKSHOP_MODIDS" ]; then
        # nothing else to do here
        return
    fi

    # delete old files in server folder, copy new files later
    if [ -d "$STEAM_WORKSHOP_MOD_DIR/" ]; then
        rm -r $STEAM_WORKSHOP_MOD_DIR
        mkdir -p $STEAM_WORKSHOP_MOD_DIR
    fi

    if [ "$1" = "-f" ]; then
        echo -e "Deleting previously downloaded workshop content for $STEAM_WORKSHOP_APPID."
        rm $STEAM_DIR/steamapps/workshop/appworkshop_$STEAM_WORKSHOP_APPID.acf
        rm -r $STEAM_DIR/steamapps/workshop/content/$STEAM_WORKSHOP_APPID
    fi

    echo -e "Downloading workshop content. If SteamCMD misses a new version, try using ./arkManage.sh update -f"
    $STEAM_CMD +runscript "$STEAMCMD_WORKSHOP" > /dev/null &
    waitBackgroundTask $!

    echo -e; echo -e;
    echo -e "Copying workshop content."
    cp -R $STEAM_DIR/steamapps/workshop/content/$STEAM_WORKSHOP_APPID/* $STEAM_WORKSHOP_MOD_DIR
}

updateCheck () {
    # Clear Steam AppCache
    if [ -d $STEAM_APPCHACHE ]; then
        rm -r $STEAM_APPCHACHE
    fi

    # check for new server version
    local Result=$($STEAM_CMD +runscript "$STEAMCMD_UPDATECHECK" | grep "Update Required")

    if [ -n "$Result" ]; then
        # update available, shut down and restart the server.
        echo -e "Found an update for the game"
        UPDATES_EXECUTABLE=1
    else
        echo -e "No updates for the game"
    fi

    # check for new workshop contents
    if [ -z "$STEAM_WORKSHOP_APPID" -o -z "$STEAM_WORKSHOP_MODIDS" ]; then
        echo -e "No workshop IDs given, not checking for new content."
        return
    fi

    local Ids=$(echo $STEAM_WORKSHOP_MODIDS | tr "," "\n")
    local OldVersion=

    for Id in $Ids; do
        OldVersion[$Id]=1
        if [ -e "$STEAM_DIR/steamapps/workshop/appworkshop_$STEAM_WORKSHOP_APPID.acf" ]; then
            OldVersion[$Id]=$(cat $STEAM_DIR/steamapps/workshop/appworkshop_$STEAM_WORKSHOP_APPID.acf | parseSteamAcf "AppWorkshop.WorkshopItemsInstalled.$Id.timeupdated")
            #echo -e "old version: ${OldVersion[$Id]}"
        else
            echo -e "No mods for app $STEAM_WORKSHOP_APPID downloaded yet."
        fi
    done

    $STEAM_CMD +runscript "$STEAMCMD_WORKSHOP" > /dev/null &
    waitBackgroundTask $!

    local NewVersion=
    for Id in $Ids; do
        NewVersion[$Id]=$(cat $STEAM_DIR/steamapps/workshop/appworkshop_$STEAM_WORKSHOP_APPID.acf | parseSteamAcf "AppWorkshop.WorkshopItemsInstalled.$Id.timeupdated")

        if [ ${NewVersion[$Id]} -gt ${OldVersion[$Id]} ]; then
            UPDATES_WORKSHOP=1
            echo -e "New workshop content for mod $Id available."
        elif [ ${NewVersion[$Id]} -eq -1 ]; then
            echo -e "Found a problem with the version of mod $Id. Is it also set to download in $STEAMCMD_WORKSHOP?"
        fi
    done

    if [ $UPDATES_WORKSHOP -eq 0 ]; then
        echo -e "No new workshop content available."
    fi
}

autoUpdate () {
    echo -e "$(date) Start of autoUpdate"
    updateCheck
    local Reason=

    if [ $UPDATES_EXECUTABLE -gt 0 -a $UPDATES_WORKSHOP -gt 0 ]; then
        Reason="Game and workshop updates"
    elif [ $UPDATES_EXECUTABLE -gt 0 ]; then
        Reason="Game updates"
    elif [ $UPDATES_WORKSHOP -gt 0 ]; then
        Reason="Workshop updates"
    fi

    if [ -n "$Reason" ]; then
        stop $SHUTDOWN_TIME_UPDATES $Reason
        # wait for the server to shut down
        sleep 30s
        updateAndStart
    fi
    echo -e "$(date) End of autoUpdate"
    echo -e
}

updateAndStart () {
    update
    start
}

# Commands
help () {
    echo -e; echo -e "Use the following commands: $RESET"
    echo -e; echo -e "./arkManage.sh <start|stop <time in minutes> <message>|update <-f>|updateCheck|autoUpdate|updateAndStart>"
    echo -e; echo -e
}

[ "$1" = "" ] && {
    help
    exit
}

$*
echo
exit 0