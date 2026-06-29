#!/bin/sh

CONFIG_FILE="constants.json"

get_json() {
    jq -c ".\"$1\"" "$CONFIG_FILE"
}

# Example usage
key_submodules="submodules"  # This key is expected to return a dictionary
key_version="version"         # This key is expected to return a single value

# Fetching the dictionary
dict=$(get_json "$key_submodules")

# Check if it's a dictionary
if [ "$dict" != "null" ]; then
    echo "Dictionary for '$key_submodules': $dict"

    # Iterate over the dictionary keys and values
    echo "$dict" | jq -r 'to_entries | .[] | "\(.key)=\(.value)"' | while IFS='=' read -r key value; do
        echo "Key: $key, Value: $value"
    done
else
    echo "No dictionary found for '$key_submodules'."
fi

# Fetching the version
version=$(get_json "$key_version")

# Check if the version is not null
if [ "$version" != "null" ]; then
    echo "Version for '$key_version': $version"
else
    echo "No version found for '$key_version'."
fi

