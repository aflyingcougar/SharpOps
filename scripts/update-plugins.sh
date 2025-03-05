#!/bin/bash

API_URL="https://api.github.com/repos"  # GitHub API URL
PLUGINS_METADATA="${SERVER_DIR}/util/plugins_metadata.json"

main() {
    # Create 'plugins.txt' if it doesn't exist
    if [[ ! -f ${SERVER_DIR}/plugins.txt ]]; then
        touch  ${SERVER_DIR}/plugins.txt
    fi
    
    _log "Checking for new plugins..."
    if check_for_new_plugins; then
        _log "Checking for plugin updates..."
        check_for_updates
    fi    
}

_log() {
    # $1: The message to log.
    # Prints the provided message to stdout with the '[PLUGIN-UPDATER]' prefix.

    local msg="${1}"
    printf '[PLUGIN-UPDATER] %s\n' "${msg}"
}

check_for_new_plugins() {
    # No inputs. Reads 'plugins.txt' and adds missing plugins to the PLUGINS_METADATA file.

    local valid_plugins=()      # from 'plugins.txt' (format: owner/repo)
    local tracked_plugins=()    # from '${SERVER_DIR}/util/plugins_metadata.json'
    local missing_plugins=()
    local author_regex='^[a-zA-Z0-9-]+$'
    local repo_regex='^[a-zA-Z0-9._-]+$'

    # Make sure 'plugins_metadata.json' exists
    if [[ ! -f ${PLUGINS_METADATA} ]]; then
        if [[ ! -d ${SERVER_DIR}/util ]]; then
            mkdir "${SERVER_DIR}/util" || { _log "Error: Failed to create '${SERVER_DIR}/util' directory" >&2; return 1; }
        fi
        echo '{}' | jq '.plugins = []' > "${PLUGINS_METADATA}"
    fi 

    # Read the 'plugins.txt' file
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Trim leading and trailing whitespace
        line=$(echo "$line" | awk '{$1=$1};1')

        # Skip empty lines
        [[ -z "$line" ]] && continue

        # Split into author and repository
        author=$(echo "$line" | cut -d'/' -f1)
        repo=$(echo "$line" | cut -d'/' -f2)

        # Validate format
        if [[ -n "$author" && -n "$repo" && "$author" =~ $author_regex && "$repo" =~ $repo_regex ]]; then
            valid_plugins+=("$line")
        else
            _log "Invalid entry skipped: $line"
        fi
    done < "${SERVER_DIR}/plugins.txt"

    # Read the PLUGINS_METADATA
    mapfile -t tracked_plugins < <(jq -r '.plugins[] | .name' "${PLUGINS_METADATA}")
    tracked_plugins_set=" ${tracked_plugins[*]} "

    # Find missing plugins
    for plugin in "${valid_plugins[@]}"; do
        repo="${plugin#*/}"
        if [[ ! $tracked_plugins_set =~ " $repo " ]]; then
            missing_plugins+=("$plugin")
            _log "New plugin found in 'plugins.txt': ${repo}"
        fi
    done

    # Populate PLUGINS_METADATA with missing plugins
    if [[ ${#missing_plugins[@]} -gt 0 ]]; then
        _log "Adding new plugins to queue for installation..."
        tmp_file=$(mktemp)
        for missing_plugin in "${missing_plugins[@]}"; do
            jq --arg plugin "${missing_plugin#*/}" \
                --arg author "${missing_plugin%%/*}" \
                --arg version "" \
                '.plugins += [{ "name": $plugin, "author": $author, "version": $version }]' \
                "${PLUGINS_METADATA}" > "$tmp_file" || { _log "Error modifying JSON" >&2; return 1; }
            
            if ! mv "$tmp_file" "${PLUGINS_METADATA}"; then
                _log "Error updating plugins metadata" >&2
                rm -f "$tmp_file"
                return 1
            fi
        done
    fi
}

check_for_updates() {
    # No inputs. Loops through all plugins and checks for updates by comparing installed and latest version.

    # Get latest version number for every plugin in PLUGINS_METADATA
    get_plugins | while read plugin; do
        local author=$(get_plugin_author "$plugin") || {
            _log "Failed to get the author of the plugin: ${plugin}. Skipping..."
            continue
        }
        local installed_version=$(get_plugin_version "$plugin") || {
            _log "Failed to get the installed version of the plugin: ${plugin}. Skipping..."
            continue
        }

        # Get latest release info from Github
        release_info=$(wget -qO- "${API_URL}/${author}/${plugin}/releases/latest") || {
            _log "Error: Unable to retrieve latest release info for '${author}/${plugin}'. Skipping..." >&2;
            continue
        }

        local tag_name=$(echo "$release_info" | jq -r '.tag_name')
        local latest_version=$(normalize_version "$tag_name")
        _log "${plugin}: Installed Version: ${installed_version}, Latest Version: ${latest_version}"

        if dpkg --compare-versions "$latest_version" gt "$installed_version"; then
            download_latest_release "$plugin" "$release_info"
        fi
    done
}

download_latest_release() {
    # $1: Plugin repo name (e.g., 'AFKManager')
    # $2: JSON release information from GitHub API (i.e., the response to 'GET /repos/{owner}/{repo}/releases/latest').
    # Downloads the latest release for the given plugin.

    local plugin_name="$1"
    local release_info="$2"
    local asset_count=$(echo "$release_info" | jq '.assets | length')
    local tag_name=$(echo "$release_info" | jq -r '.tag_name')
    local latest_version=$(normalize_version "$tag_name")

    if [[ "$asset_count" -eq 0 ]]; then
        _log "No downloadable assets found for ${plugin_name}. Skipping."
        return 1
    fi

    if [[ "$asset_count" -eq 1 ]]; then
        local temp_dir=$(mktemp -d) || {
            _log "Error: Failed to create temporary directory" &>2
            return 1
        }

        # _log "Created temporary directory: ${temp_dir}"

        # Extract the download URL for the zip file (tarball or zip based on availability)
        local download_url=$(echo "$release_info" | jq -r '.assets[0].browser_download_url')
        archive_name=$(basename "$download_url")

        if [ -n "$download_url" ]; then
            _log "${plugin_name}: Downloading from $download_url..."
            wget -qP "$temp_dir" "$download_url" || {
                _log "Error: Failed to download ${plugin_name}. Skipping." >&2
                return 1
            }
            _log "${plugin_name}: Download complete."
        else
            _log "No release found for $repo."
        fi

        if install_plugin "$plugin_name" "${temp_dir}/${archive_name}"; then
            _log "-------${plugin} updated succesfully!-------"

            set_plugin_version "$plugin_name" "$latest_version"
        fi

        rm -rf "$temp_dir"
        return 0
    else
        _log "Warning: Multiple assets found for ${plugin_name}. Skipping."
        return 1
    fi
}

extract_plugin_archive() {
    # $1: Full path to the downloaded plugin archive (e.g. '/tmp/pluginName_v2.0.0.zip')
    # Extracts a plugin archive to the parent directory and returns the full path to the extracted root
    local plugin_archive="$1"
    local plugin_archive_dir=${plugin_archive%/*}

    if [[ ! -f "$plugin_archive" ]]; then
        _log "Error: Missing required argument: plugin_archive" >&2
        return 1
    fi

    case "$plugin_archive" in
        *.zip) unzip -qd "$plugin_archive_dir" "$plugin_archive" || return 1 ;;
        *.tar.gz) tar -xzf "$plugin_archive" -C "$plugin_archive_dir" || return 1 ;;
        *.tar) tar -xf "$plugin_archive" -C "$plugin_archive_dir" || return 1 ;;
        *) _log "Error: Unsupported file type. Only .zip, .tar.gz, and .tar are supported." >&2
            return 1 ;;
    esac

    # Find all extracted top-level directories and return them
    local extracted_roots=($(find "$plugin_archive_dir" -mindepth 1 -maxdepth 1 -type d))

    if [[ ${#extracted_roots[@]} -gt 0 ]]; then
        printf "%s\n" "${extracted_roots[@]}"   # Return all directories as separate lines
    else
        _log "Error: Failed to detect extracted root directory." >&2
        return 1
    fi
}

get_plugin_author() {
    # $1: plugin name (e.g., 'AFKManager')
    # Returns the author of the specified plugin from the PLUGINS_METADATA file.

    local plugin_name="$1"

    if [[ -z "$plugin_name" ]]; then
        _log "Error: Plugin name is empty." >&2
        return 1
    fi

    if [[ ! -f "${PLUGINS_METADATA}" ]]; then
        _log "Error: plugins_metadata.json does not exist." >&2
        return 1
    fi

    local author=$(jq -r --arg plugin "$plugin_name" '.plugins[] | select(.name == $plugin) | .author' ${PLUGINS_METADATA})

    if [[ -z "$author" || "$author" == "null" ]]; then
        _log "Error: No author found for plugin '${plugin_name}' in the PLUGINS_METADATA file." >&2
        return 1
    fi

    echo "$author"
}

get_plugin_version() {
    # $1: plugin name (e.g., 'AFKManager')
    # Returns the installed version of the specified plugin from the PLUGINS_METADATA file.

    local plugin_name="$1"

    if [[ -z "$plugin_name" ]]; then
        _log "Error: Plugin name is empty." >&2
        return 1
    fi

    if [[ ! -f "${PLUGINS_METADATA}" ]]; then
        _log "Error: plugins_metadata.json does not exist." >&2
        return 1
    fi

    local version=$(jq -r --arg plugin "$plugin_name" '.plugins[] | select(.name == $plugin) | .version' ${PLUGINS_METADATA}) || {
        _log "Error: Failed JSON query to PLUGINS_METADATA."
        return 1
    }

    if [[ "$version" == "null" ]]; then
        _log "Error: Invalid version (null) found for plugin '${plugin_name}' in the PLUGINS_METADATA file." >&2
        return 1
    fi

    echo "$version"  
}

get_plugins() {
    # No inputs. Returns all plugin names from the PLUGINS_METADATA file.

    if [[ ! -f "${PLUGINS_METADATA}" ]]; then
        _log "Error: plugins_metadata.json does not exist." >&2
        return 1
    fi

    local plugins=$(jq -r '.plugins[].name' ${PLUGINS_METADATA})

    if [[ -z "$plugins" || "$plugins" == "null" ]]; then
        _log "Error: No plugins found in the PLUGINS_METADATA file." >&2
        return 1
    fi

    echo "${plugins[@]}" 
}

install_plugin() {
    # $1: Plugin repo name (e.g., 'AFKManager') 
    # $2: Full path to the downloaded plugin archive (e.g. '/tmp/pluginName_v2.0.0.zip')
    # Installs the provided plugin

    local plugin_name="$1"
    local plugin_archive="$2"

    # Extract plugin archive
    local extracted_roots=($(extract_plugin_archive "$plugin_archive")) || return 1
    
    for extracted_root in "${extracted_roots[@]}"; do
        move_plugin_file "$extracted_root" "$plugin_name" || return 1
    done

}

move_plugin_file() {
    # $1: Full path to the extracted plugin
    #   (e.g. /tmp/pluginName_v2.0.0.zip  [extracted to]--> /tmp/pluginName_v2.0.0)
    # $2: Plugin name (e.g., 'AFKManager')
    # Analyzes an extracted plugin, and moves the files to the proper server path
    
    local extracted_root="$1"
    local plugin_name="$2"
    local is_first_install=0
    local rsync_opts=(-aq)
    local target_dir
    local plugin_dir_name
    local local_version=$(get_plugin_version "$plugin_name") || {
        _log "Error: failed to get plugin version. Skipping..." >&2
        return 1
    }

    [[ -n "$local_version" ]] && is_first_install=1 # Not first-time install

    if [[ $is_first_install -eq 1 ]]; then
        rsync_opts+=(
            --exclude="*.json"      # Exclude all .json files
            --include="*.deps.json" # But allow *.deps.json files
            --exclude="*.txt"
            --exclude="*.cfg"
        )
    fi

    plugin_dir_name=$(basename "${extracted_root}") || {
        _log "Error: failed to get plugin directory name. Skipping..." >&2
        return 1
    }
    case "$extracted_root" in
        */addons)
            _log "${plugin_name}: Detected archive with 'addons/' as root. Moving files to ${SERVER_DIR}/game/csgo"
            target_dir="${SERVER_DIR}/game/csgo/addons"
            ;;
        */cfg)
            _log "${plugin_name}: Detected archive with 'cfg/' as root. Moving files to ${SERVER_DIR}/game/csgo"
            target_dir="${SERVER_DIR}/game/csgo/cfg"
            ;;
        */counterstrikesharp)
            _log "${plugin_name}: Detected archive with 'counterstrikesharp/' as root. Moving files to ${SERVER_DIR}/game/csgo/addons"
            target_dir="${SERVER_DIR}/game/csgo/addons/counterstrikesharp"
            ;;
        */plugins|*/configs|*/shared)
            _log "${plugin_name}: Detected archive with '${plugin_dir_name}' as root. Moving files to ${SERVER_DIR}/game/csgo/addons/counterstrikesharp"
            target_dir="${SERVER_DIR}/game/csgo/addons/counterstrikesharp/${plugin_dir_name}"
            ;;
        *)
            _log "${plugin_name}: Detected archive with '${plugin_dir_name}' as root. Moving files to ${SERVER_DIR}/game/csgo/addons/counterstrikesharp/plugins"
            [[ -d "${SERVER_DIR}/game/csgo/addons/counterstrikesharp/plugins/${plugin_dir_name}" ]] ||
                mkdir "${SERVER_DIR}/game/csgo/addons/counterstrikesharp/plugins/${plugin_dir_name}" ||
                return 1
            target_dir="${SERVER_DIR}/game/csgo/addons/counterstrikesharp/plugins/${plugin_dir_name}"
            ;;
    esac

    rsync "${rsync_opts[@]}" "${extracted_root}/" "${target_dir}" || {
        _log "Error: Failed to move the plugin files for ${plugin_name}. Skipping" >&2
        return 1
    }
    
    return 0
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

set_plugin_version() {
    # $1: plugin name (e.g., 'AFKManager')
    # $2: new plugin version (e.g., '1.0.2')
    # Updates a plugin version in the PLUGINS_METADATA file.

    local plugin_name="$1"
    local new_version="$2"
    local tmp_file=$(mktemp)

    jq --arg name "$plugin_name" \
        --arg version "$new_version" \
        '(.plugins[] | select(.name == $name)).version = $version' \
        "${PLUGINS_METADATA}" > "$tmp_file" || { _log "Error modifying JSON" >&2; return 1; }

    if ! mv "$tmp_file" "${PLUGINS_METADATA}"; then
        _log "Error updating plugins metadata" >&2
        rm -f "$tmp_file"
        return 1
    fi

    return 0
}

main "$@"