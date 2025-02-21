#!/bin/bash

main() {
    _log "Checking for Metamod files..."
        if [ ! -f ${SERVER_DIR}/game/csgo/addons/metamod.vdf ]; then
            _log "Metamod files not found, checking for latest dev build..."
            metamod_url=$(
                wget -qO- "https://www.sourcemm.net/downloads.php?branch=dev" |
                grep -oP "https://mms\.alliedmods\.net/mmsdrop/[^']+linux\.tar\.gz" |
                head -n 1
            )

            if [ -n $metamod_url ]; then
                _log "Latest Metamod dev build found at: ${metamod_url}"
            else
                _log "Failed to find the URL for the latest Metamod dev build" >&2; exit 1
            fi
            
            _log "Downloading Metamod..."
            wget -qO /tmp/metamod.tar.gz $metamod_url || { _log "Error: Failed to download Metamod" >&2; exit 1; }
            tar -xzf /tmp/metamod.tar.gz -C ${SERVER_DIR}/game/csgo || { _log "Error: Failed to extract Metamod" >&2; exit 1; }
            _log "Installed Metamod!"
        else
            _log "Metamod found! Continuing..."
        fi

        _log "Metamod: adjusting gameinfo file..."
        metamod_fix

        _log "Checking for CounterStrikeSharp files..."
        if [ ! -f ${SERVER_DIR}/game/csgo/addons/counterstrikesharp/bin/linuxsteamrt64/counterstrikesharp.so ]; then
            _log "CounterStrikeSharp files not found, checking for latest release..."
            css_url=$(  
                wget -qO- https://api.github.com/repos/roflmuffin/CounterStrikeSharp/releases/latest |
                jq -r '.assets[] | select(.name | test("runtime.*linux")) | .browser_download_url'
            )

            if [ -n $css_url ]; then
                _log "Latest CounterStrikeSharp build found at: ${css_url}"
            else
                _log "Failed to find the URL for the latest CounterStrikeSharp build" >&2; exit 1
            fi

            _log  "Downloading CounterStrikeSharp..."
            wget -qO /tmp/counterstrikesharp.zip $css_url || { _log "Error: Failed to download CounterStrikeSharp" >&2; exit 1; }
            unzip -qd ${SERVER_DIR}/game/csgo /tmp/counterstrikesharp.zip || { _log "Error: Failed to extract CounterStrikeSharp" >&2; exit 1; }
            _log "Installed CounterStrikeSharp!"
        else
            _log "CounterStrikeSharp found! Continuing..."
        fi
}

_log() {
    local msg="${1}"
    printf '[install-css] %s\n' "${msg}"
}

metamod_fix() {
  local gameinfo_file="${SERVER_DIR}/game/csgo/gameinfo.gi"
  local mm_search_path="csgo/addons/metamod"
  local mm_search_path_whitespace="           Game    csgo/addons/metamod"
  local keyword="csgo_lv"

  if ! grep -Fq $mm_search_path $gameinfo_file; then
    sed -i "/$keyword/a\ $mm_search_path_whitespace" "$gameinfo_file"
    _log "Added the Metamod SearchPath after '${keyword}'"
  else
    _log "Metamod SearchPath already exists, skipping."
  fi 
}

main "$@"