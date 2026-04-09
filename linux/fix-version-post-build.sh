#!/bin/bash

# This script is for setting correct values in the version.json
# Currently for some reason the package_name and app_name are just the same as the name in pubspec.yaml

json_path="./build/linux/x64/release/bundle/data/flutter_assets/version.json"

echo "Fixing $(pwd)/$json_path"

# Read the JSON content
json=$(<"$json_path")
app_name=$(echo "$json" | jq -r '.app_name')
package_name=$(echo "$json" | jq -r '.package_name')

# Make sure this issue wasn't fixed upstream yet
if [[ "$app_name" == "hedon_haven" && "$package_name" == "hedon_haven" ]]; then
  echo "version.json not fixed. Fixing..."
  if [ -n "$1" ]; then
    echo "Using suffix: $1"
    json=$(echo "$json" | jq --arg suffix "$1" '.app_name = "Hedon Haven ($suffix)" | .package_name = ("com.hedon_haven.viewer." + $suffix)')
  else
    echo "Adding without any suffix"
    json=$(echo "$json" | jq '.app_name = "Hedon Haven" | .package_name = "com.hedon_haven.viewer"')
  fi
  echo "$json" > "$json_path"
else
  echo "version.json already fixed. Skipping..."
fi

echo "Finished fixing version.json files"