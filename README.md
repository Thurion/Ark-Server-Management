# Ark-Server-Management
For easier management of my Ark server. Feel free to use the scripts but be aware, that they might need to be customized.

Installation
--------

Warning: A little knowledge of how to use the command line and Git are necessary because this is a basic installation guide.

1.  Install steamCMD, the Ark server and screen
2.  Get [mcrcon](https://github.com/Tiiffi/mcrcon/ "mcrcon") and compile it
3.  Clone this repository
4.  Create a copy of config.conf.example and edit the fields
5.  Create a copy of ark_workshop_update.txt.example if you want to use mods. You need to add a valid user who owns the game.
6.  Edit arkManage.sh and set the path to the config to your config
7.  Make script executable
8.  If using mods, start SteamCMD and log into your account once because SteamCMD needs to be authenticated (Steam Guard) first. If using a mobile authenticator, switch to email guard codes.

Usage
--------

Running the script without any arguments prints a basic help line:  
`/arkManage.sh <start|stop <time in minutes> <message>|update <-f>|updateCheck|autoUpdate|updateAndStart>`

* **start** starts the server in a new screen session if no server is running at the moment
* **stop** stops the server via RCON. Time and message are optional.
* **update** is meant for manual updates. Updates the server and workshop (if used). If SteamCMD doesn't recongnize an updated mod, use option "-f"
* **updateCheck** checks for new server and workshop updates
* **autoUpdate** is meant to use in a cron jobs. It checks for new updates and if there is one, it stops the server, does the update and starts it afterwards.
* **updateAndStart** usage of update and start for your convenience ;)

Limitations
--------

* Supports only one server
* updateCheck only finds an update once for each update because newer versions are downloaded in the process.
* Not ready for stackable mods which will be available in the near future
