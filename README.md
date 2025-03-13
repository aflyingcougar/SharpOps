!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

![Docker workflow](https://github.com/aflyingcougar/SharpOps/actions/workflows/docker-publish.yml/badge.svg)

## SharpOps

SharpOps is a Docker container built on [`ich777/steamcmd:cs2`](https://github.com/ich777/docker-steamcmd-server/tree/cs2), designed to automate the setup and management of Counter-Strike 2 dedicated servers with CounterStrikeSharp (CSS) and its dependencies. This container simplifies server administration by:

- Automatically installing Metamod & CounterStrikeSharp and keeping them updated
- Managing compatible plugins, ensuring they stay up-to-date
- Handling SteamCMD configuration and CS2 server installation
- Providing a streamlined solution for modded CS2 servers

This project is ideal for server administrators looking for an easy way to deploy and maintain a fully modded CS2 experience with minimal manual intervention. 🚀

## Features
 - [x] Metamod auto-install & update
 - [x] CounterStrikeSharp auto-install & update
 - [x] CounterStrikeSharp plugins auto-install & update*
 - [ ] Add compatibility for plugins with multiple assets
 - [ ] Allow users to specify the build/release version of each plugin in `plugins.txt`, rather than always downloading the latest release.


## Environment Variables 

| Variable Name       | Default Value | Description |
|---------------------|--------------|-------------|
| `UPDATE_PLUGINS` | `true` | When set to `true`, the container will attempt to install/update all compatible plugins in `plugins.txt` on each boot. |


### Additional Environment Variables
Since this image is based on [`ich777/steamcmd:cs2`](https://github.com/ich777/docker-steamcmd-server/tree/cs2), the following additional environment variables are also available for configuration. Please refer to the base image documentation for details.
| Variable Name| Default Value | Description |
|-|-|-|
| `GAME_PARAMS` | _(unset)_ | List of space-delimited command-line parameters and console variables to pass to the `cs2` executable file. For more info, see the [Official Docs](https://developer.valvesoftware.com/wiki/Counter-Strike_2/Dedicated_Servers#Command-Line_Parameters) |
| `VALIDATE` | _(unset)_ | When set to `true`, SteamCMD will validate all of the server files. This command is useful if you think that files may be missing or corrupted. For more info, see the [Official Docs](https://developer.valvesoftware.com/wiki/SteamCMD#Validate). |
| `USER` | `steam` | The system username under which the server process runs. |
| `UID` | `99` | Defines the User ID of the container user (`steam`). |
| `GID` | `100` | Defines the Group ID of the container user (`steam`). |

