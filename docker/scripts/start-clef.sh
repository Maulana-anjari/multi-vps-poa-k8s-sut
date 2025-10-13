#!/usr/bin/expect -f
# File: scripts/start-clef.sh
# This script automates the startup of a Clef signer instance, making it suitable for non-interactive
# environments like a Docker container.

# Retrieve the master password from an environment variable.
# This is a best practice for passing secrets to containers, typically set in the docker-compose.yml file.
set clef_master_password $env(CLEF_MASTER_PASSWORD)

# Retrieve other required configuration from environment variables.
set chain_id $env(NETWORK_ID)
set keystore_path "/root/.ethereum/keystore"
set config_dir "/root/.clef"
set rules_path "/root/rules.js"

# Ensure Clef masterseed has restrictive permissions to avoid insecure warning
if {[file exists "$config_dir/masterseed.json"]} {
    exec chmod 0400 "$config_dir/masterseed.json"
}

# Set an infinite timeout to prevent the script from exiting if Clef is slow to start.
set timeout -1

# Spawn the Clef process with the necessary parameters.
# --suppress-bootwarn is added for cleaner logs on startup.
spawn clef \
    --keystore $keystore_path \
    --configdir $config_dir \
    --chainid $chain_id \
    --rules $rules_path \
    --nousb \
    --advanced \
    --http --http.addr 0.0.0.0 --http.port 8550 --http.vhosts "*" \
    --suppress-bootwarn

# --- Automation Sequence ---
# This loop handles Clef's startup prompts in a robust way.
expect {
    -re "Password|password" {
        send "$clef_master_password\n"
        exp_continue
    }
    "Enter 'ok' to proceed:" {
        send "ok\n"
        exp_continue
    }
    "Approve? \[y/N\]:" {
        send "y\n"
        exp_continue
    }
    eof
}
