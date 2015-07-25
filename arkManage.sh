#!/bin/bash

source /home/ark/scripts/config.conf

UPDATES_EXECUTABLE=0
UPDATES_WORKSHOP=0
STEAM_APPCHACHE=STEAM_DIR/appcache

parseConfig() {
    RCON_PW=$(cat $CONFIG | grep $CFG_RCON_PW | cut -d'=' -f2)
    RCON_PORT=$(cat $CONFIG | grep $CFG_RCON_PORT| cut -d'=' -f2)
}

msgServerMinutes() {
    local Message="${@:2}"
    if [ -z "$Message" ]; then
        Message="No reason given"
    fi
	$MCRCON -s -H $RCON_HOST -P $RCON_PORT -p $RCON_PW "Broadcast Server shutting down in $1 minutes. Reason: $Message"
	echo -e "Server shutting down down in $1 minutes. Reason: $Message"
}

msgServerSeconds() {
    local Message="${@:2}"
    if [ -z "$Message" ]; then
        Message="No reason given"
    fi
	$MCRCON -s -H $RCON_HOST -P $RCON_PORT -p $RCON_PW "Broadcast Server shutting down in $1 seconds. Reason: $Message"
	echo -e "Server shutting down in $1 seconds. Reason: $Message"
}

countDown() {
	msgServerSeconds 60
    echo -e "Shut down in 60 seconds."
	sleep 30s
	msgServerSeconds 30
    echo -e "Shut down in 30 seconds."
	sleep 15s
	local timer=15
	while [ $timer -gt 0 ]; do
		msgServerSeconds $timer
        echo -e "Shut down in $timer."
		sleep 1s
		let timer-=1
	done

	# stop server
	$MCRCON -s -H $RCON_HOST -P $RCON_PORT -p $RCON_PW $RCON_STOP
}

# taken from https://github.com/Zendrex/ARK-Linux-Server-Script
function waitBackgroundTask
{
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
function parseSteamAcf
{
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
    
    echo "NOT FOUND! ERROR?"
}

start () {
    if screen -list | grep -q $SCREEN; then
        echo -e "Screen session is already running. Checking if there is a server process ..."
        
        if [ $(ps ux | grep -o "$EXECUTABLE" | wc -l) -gt 2 ]; then # ps gives 3 results
            echo -e "Server is already running. Exiting ..."
            echo -e;
            exit
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
    if [ ! $(screen -list | grep -q $SCREEN) ]; then
        echo -e "No server is running. Doing nothing."
        return
    fi

    if [ -z "$RCON_PW" -o -z "$RCON_PORT" ]; then
        parseConfig
    fi
    
    if [ -z "$RCON_PW" -o -z "$RCON_PORT" ]; then
        echo "Error parsing config or no RCON values provided"
        exit 1
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
        msgServerMinutes $Time $Message
        
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
        msgServerMinutes $Time $Message
        # wait until there is 1 minute left
        sleep $((($Time-1)*60))
        Time=1
    fi

    countDown
}

update () {
    $STEAM_CMD +runscript "$STEAMCMD_UPDATE"
    
    if [ -z "$STEAM_WORKSHOP_APPID" -o -z "$STEAM_WORKSHOP_MODID" ]; then
        # nothing else to do here
        continue
    fi
    
    if [ -d "$STEAM_WORKSHOP_MOD_DIR/$STEAM_WORKSHOP_MODID" ]; then
        rm -r $STEAM_WORKSHOP_MOD_DIR/$STEAM_WORKSHOP_MODID
    fi
    
    echo -e; echo -e;
    echo -e "Copying workshop content."
    cp -R $STEAM_DIR/steamapps/workshop/content/$STEAM_WORKSHOP_APPID/$STEAM_WORKSHOP_MODID $STEAM_WORKSHOP_MOD_DIR
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
    if [ -z "$STEAM_WORKSHOP_APPID" -o -z "$STEAM_WORKSHOP_MODID" ]; then
        echo -e "No workshop IDs given, not checking for new content."
        return
    fi
    
    local OldVersion=1
    if [ -e "$STEAM_DIR/steamapps/workshop/appworkshop_346110.acf" ]; then
        OldVersion=$(cat $STEAM_DIR/steamapps/workshop/appworkshop_346110.acf | parseSteamAcf "AppWorkshop.WorkshopItemsInstalled.$STEAM_WORKSHOP_MODID.timeupdated")
        #echo -e "old version: $OldVersion"
    else
        echo -e "Mod $STEAM_WORKSHOP_MODID not yet downloaded"
    fi
    
    $STEAM_CMD +runscript "$STEAMCMD_WORKSHOP" > /dev/null &
    waitBackgroundTask $!
    
    local NewVersion=$(cat $STEAM_DIR/steamapps/workshop/appworkshop_346110.acf | parseSteamAcf "AppWorkshop.WorkshopItemsInstalled.$STEAM_WORKSHOP_MODID.timeupdated")
    #echo -e "new version: $NewVersion"
    
    if [ $NewVersion -gt $OldVersion ]; then
      echo -e "New workshop content available"  
      UPDATES_WORKSHOP=1
    fi
    
}

autoUpdate () {
    updateCheck
    local Reason=
    
    if [ $UPDATES_EXECUTABLE -a $UPDATES_WORKSHOP ]; then
        Reason="Game and workshop updates"
    elif [ $UPDATES_EXECUTABLE ]; then
        Reason="Game updates"
    elif [ $UPDATES_WORKSHOP ]; then
        Reason="Workshop updates"
    fi
    
    stop 15 $Reason
    updateAndStart
}

updateAndStart () {
    update
    start
}

# Commands
help () {
    echo -e; echo -e "Use the following commands: $RESET"
    echo -e; echo -e "./arkManage.sh <start|stop <time in minutes> <message>|update|updateCheck|autoUpdate|updateAndStart>"
    echo -e; echo -e
}

[ "$1" = "" ] && {
    help
    exit
}

$*
echo
exit 0