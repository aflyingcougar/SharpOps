#!/bin/bash

METAMOD_DIR="${SERVER_DIR}/game/csgo/addons/metamod"
METAMOD_RELEASES_URL="https://www.sourcemm.net/downloads.php?branch=dev"
CSS_DIR="${SERVER_DIR}/game/csgo/addons/counterstrikesharp"
CSS_RELEASES_URL="https://api.github.com/repos/roflmuffin/CounterStrikeSharp/releases/latest"

main() {
    # Get current metamod version
    if [[ -f ${METAMOD_DIR}/version ]]; then
        metamod_version=$(< "${METAMOD_DIR}/version")
    else
        metamod_version=""
    fi
    metamod_update
    metamod_fix

    # Get current CounterStrikeSharp version
    if [[ -f ${CSS_DIR}/version ]]; then
        css_version=$(< "${CSS_DIR}/version")
    else
        css_version=""
    fi
    css_update
}

_log() {
    local msg="${1}"
    printf '[CSS-UPDATER] %s\n' "${msg}"
}

css_update() {
    # Check if there is a newer version of CounterStrikeSharp available
    css_url=$(  
        wget -qO- "${CSS_RELEASES_URL}" |
        jq -r '.assets[] | select(.name | test("runtime.*linux")) | .browser_download_url'
    )
    css_url_version=$(
        echo $css_url | awk -F'/' '{print $8}'
    )
    css_url_version=$(normalize_version "$css_url_version")

    # Update if newer version available, otherwise continue
    if [[ -n $css_url && -n $css_url_version ]]; then
        if dpkg --compare-versions "$css_url_version" gt "$css_version"; then
            _log "A newer version of CounterStrikeSharp was found: Build ${css_url_version} at ${css_url}"
            _log "Downloading CounterStrikeSharp..."
            wget -qO /tmp/counterstrikesharp.zip $css_url || { _log "Error: Failed to download CounterStrikeSharp" >&2; exit 1; }
            unzip -qod ${SERVER_DIR}/game/csgo /tmp/counterstrikesharp.zip || { _log "Error: Failed to extract CounterStrikeSharp" >&2; exit 1; }
            echo $css_url_version > ${CSS_DIR}/version || { _log "Error: failed to update CounterStrikeSharp version file" >&2; exit 1; }
            _log "CounterStrikeSharp updated to Build ${css_url_version}!"
        else
            _log "CounterStrikeSharp is already up to date: Build ${css_version}"
        fi 
    else
        _log "Failed to determine the latest release of CounterStrikeSharp from the upstream repository! Maybe the website is down?"
    fi
}

metamod_fix() {
    local gameinfo_file="${SERVER_DIR}/game/csgo/gameinfo.gi"
    local mm_search_path="csgo/addons/metamod"
    local mm_search_path_whitespace="           Game    csgo/addons/metamod"
    local keyword="csgo_lv"

    _log "Metamod: adjusting gameinfo file..."
    if ! grep -Fq "$mm_search_path" "$gameinfo_file"; then
    sed -i "/$keyword/a\ $mm_search_path_whitespace" "$gameinfo_file"
    _log "Added the Metamod SearchPath after '${keyword}'"
    else
    _log "Metamod SearchPath already exists, skipping."
    fi 
}

metamod_update() {
    # Check if there is a newer version of Metamod available
    metamod_url=$(
        wget -qO- "${METAMOD_RELEASES_URL}" |
        grep -oP "https://mms\.alliedmods\.net/mmsdrop/[^']+linux\.tar\.gz" |
        head -n 1
    )
    metamod_url_version=$(
        echo $metamod_url | awk -F'git' '{print $2}' | grep -oE '^[0-9]+'
    )
    
    # Update if newer version available, otherwise continue
    if [[ -n $metamod_url && -n $metamod_url_version ]]; then
        if [[ $metamod_url_version -gt $metamod_version ]]; then
            _log "A newer version of Metamod was found: Build ${metamod_url_version} at ${metamod_url}"
            _log "Downloading Metamod..."
            wget -qO /tmp/metamod.tar.gz $metamod_url || { _log "Error: Failed to download Metamod" >&2; exit 1; }
            tar -xzf /tmp/metamod.tar.gz -C ${SERVER_DIR}/game/csgo || { _log "Error: Failed to extract Metamod" >&2; exit 1; }
            echo $metamod_url_version > ${METAMOD_DIR}/version || { _log "Error: failed to update Metamod version file" >&2; exit 1; }
            _log "Metamod updated to version ${metamod_url_version}!"
        else
            _log "Metamod is already up to date: Build ${metamod_version}"
        fi 
    else
        _log "Failed to determine the latest release of Metamod from the upstream repository! Maybe the website is down?"
    fi
}

normalize_version() {
    # $1: version string (e.g., 'v1.2.3' or 'build-1234')
    # Returns the normalized version string by removing unnecessary prefixes and characters.

    if [[ -z "$1" ]]; then
        _log "Error: No version string provided" >&2
        return 1
    fi

    # Normalize the version string: remove 'v' and 'build-' prefixes
    local version="$1"
    version=$(echo "$version" | tr '[:upper:]' '[:lower:]')
    version="${version#v}"
    version="${version//[^0-9.]/}"

    echo "$version"
}

main "$@"