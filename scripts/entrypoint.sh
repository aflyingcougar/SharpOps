#!/bin/bash

main() {
    _log "Running original entrypoint..."
    /opt/scripts/start.sh &
    start_pid="$!"

    # Wait for the 'cs2' process to start
    while ! pgrep -x "cs2" > /dev/null; do
        sleep 1
    done

    _log "Stopping the CS2 server to install/update Metamod and CounterStrikeSharp"
    cs2_pid=$(pgrep -x "cs2")
    if [[ -n "$cs2_pid" ]]; then
        kill -SIGTERM "$cs2_pid" 2>/dev/null
        wait "$cs2_pid" 2>/dev/null
    fi

    _log "Waiting for the original entrypoint to exit"
    wait $start_pid 2>/dev/null
    _log "CS2 server stopped."

    # Only let SteamCMD validate once
    if [[ ${VALIDATE} == "true" ]]; then
        VALIDATE="false"
    fi

    # Update Metamod and CounterStrikeSharp
    su ${USER} -c "/opt/scripts/update-css.sh"
    
    # Update CounterStrikeSharp plugins (optional)
    if [[ ${UPDATE_PLUGINS} == "true" ]]; then
        su ${USER} -c "/opt/scripts/update-plugins.sh"    
    fi

    # Finally, run original installation/setup again
    exec /opt/scripts/start.sh

}

_log() {
    local msg="${1}"
    printf '[CSS-UPDATER] %s\n' "${msg}"
}

main "$@"
