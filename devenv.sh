#!/usr/bin/env bash

# Wrapper around docker compose to standardise devcontainer development
# utilising gh:karnull/switchboard.nvim .commands file.
# shortcuts to generalise common commands that differ consistently across projects
# expects the template layout: .devcontainer/compose.yaml holding a single dev service

COMMANDS_FILE=".commands"
COMPOSE_FILE=".devcontainer/compose.yaml"
SERVICE="dev"
BASE_IMAGE="dev-base:latest"
# host checkout of this repo, holds the base Dockerfile and the templates
DEV_BASE_DIR="${DEV_BASE_DIR:-$HOME/.local/dev-base}"
ACTION=$1
shift

# cd to project root if inside git repo
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    cd "$(git rev-parse --show-toplevel)"
fi

# the compose build args read these, UID and GID themselves are readonly in bash
export DEV_UID="$(id -u)"
export DEV_GID="$(id -g)"


#-------------------------------------------------------------------------------
# help menu

show_help() {
cat <<'EOF'
Usage: script [action] [args...]

Actions:
  up              start dev container
  down            stop dev container
  restart         restart dev container
  delete          remove dev container
  build           rebuild dev container image
  exec <CMD>      run CMD in dev container
  connect         open shell in dev container
  claude [args]   run claude in dev container
  list            list docker containers

Templates:
  tsetup          copy the full template .devcontainer into this project
  tmsetup         copy the mini template .devcontainer into this project
  tupdate         rebuild the dev-base:latest image from the base Dockerfile

Other:
  <action>        run entry from .commands file

Notes:
  - runs from git repo root if present
  - requires .devcontainer/compose.yaml with a dev service
  - requires the dev-base:latest image, build it with tupdate
  - templates and the base Dockerfile are read from $DEV_BASE_DIR
    (default ~/.local/dev-base, override by exporting DEV_BASE_DIR)
  - requires .commands for custom actions
EOF
}

if [ -z "$ACTION" ]; then
    show_help
    exit 0
fi


#-------------------------------------------------------------------------------
# helper functions

# the compose file owns the project name, but compose would otherwise derive it from
# the directory holding the file, which is .devcontainer for every project alike
project_name() {
    local result

    if [ -f "$COMPOSE_FILE" ]; then
        result=$(grep '^name:' "$COMPOSE_FILE" | cut -d ' ' -f 2)
    fi

    echo "${result:-${PWD##*/}}"
}

# relative paths in the compose file resolve against its own directory, so the project
# directory is left alone here and only the name is passed in
compose() {
    docker compose -f "$COMPOSE_FILE" -p "$PROJECT" "$@"
}

require_compose_file() {
    if [ ! -f "$COMPOSE_FILE" ]; then
        echo -e "\033[31mError: $COMPOSE_FILE not found\033[0m"
        exit 1
    fi
}

require_base_image() {
    if ! docker image inspect "$BASE_IMAGE" >/dev/null 2>&1; then
        echo -e "\033[33m! No $BASE_IMAGE image found\033[0m"
        echo -e "\033[34m! Build it with:\033[0m"
        echo -e "\033[34m!   $(basename "$0") tupdate\033[0m"
        exit 1
    fi
}

start_container() {
    require_base_image
    compose up -d "$SERVICE"
}

ensure_running() {
    if [ -z "$(compose ps --quiet --status running "$SERVICE")" ]; then
        echo -e "\033[34m! No running $SERVICE container, starting one\033[0m"
        start_container
    fi
}

# copies <template>/.devcontainer into the project, refusing to clobber an existing one
# unless told to. the compose project name is rewritten to the project directory, otherwise
# every project copied from the same template would share one compose project
copy_template() {
    local template=$1 force=$2
    local source="$DEV_BASE_DIR/$template/.devcontainer"
    local target=".devcontainer"

    if [ ! -d "$source" ]; then
        echo -e "\033[31mError: template not found: $source\033[0m"
        exit 1
    fi

    if [ -e "$target" ]; then
        if [ "$force" != "force" ]; then
            echo -e "\033[31mError: $target already exists, pass -f to overwrite\033[0m"
            exit 1
        fi
        echo -e "\033[33m! Overwriting existing $target\033[0m"
        rm -rf "$target"
    fi

    cp -R "$source" "$target"

    if [ -f "$target/compose.yaml" ]; then
        sed -i.bak "s|^name:.*|name: ${PWD##*/}|" "$target/compose.yaml"
        rm -f "$target/compose.yaml.bak"
    fi

    echo -e "\033[34m> copied $source to $PWD/$target\033[0m"
}

PROJECT=$(project_name)


#-------------------------------------------------------------------------------
# special commands

case "$ACTION" in
    start|up)
        require_compose_file
        start_container
        exit 0
        ;;

    stop|down)
        require_compose_file
        compose stop "$SERVICE"
        exit 0
        ;;

    restart|r)
        require_compose_file
        compose stop "$SERVICE"
        start_container
        exit 0
        ;;

    delete|rm)
        require_compose_file
        compose down
        exit 0
        ;;

    build|b)
        require_compose_file
        require_base_image
        compose build "$SERVICE"
        exit 0
        ;;

    exec|e)
        if [ -z "$1" ]; then
            echo -e "\033[31mError: no command provided\033[0m"
            exit 1
        fi
        require_compose_file
        ensure_running
        compose exec "$SERVICE" bash -c "$*"
        exit 0
        ;;

    connect|c)
        require_compose_file
        ensure_running
        compose exec "$SERVICE" bash
        exit 0
        ;;

    claude|cc)
        require_compose_file
        ensure_running
        compose exec "$SERVICE" claude "$@"
        exit 0
        ;;

    list|l|ls)
        docker container list
        exit 0
        ;;

    tsetup)
        copy_template "template" "$([ "$1" = "-f" ] || [ "$1" = "--force" ] && echo force)"
        exit 0
        ;;

    tmsetup)
        copy_template "template-mini" "$([ "$1" = "-f" ] || [ "$1" = "--force" ] && echo force)"
        exit 0
        ;;

    tupdate)
        if [ ! -f "$DEV_BASE_DIR/Dockerfile" ]; then
            echo -e "\033[31mError: no Dockerfile in $DEV_BASE_DIR\033[0m"
            exit 1
        fi
        echo -e "\033[34m> rebuilding $BASE_IMAGE from $DEV_BASE_DIR\033[0m"
        docker build -t "$BASE_IMAGE" \
            --build-arg UID="$DEV_UID" \
            --build-arg GID="$DEV_GID" \
            "$@" "$DEV_BASE_DIR"
        exit $?
        ;;

    --help|-h|help|h)
        show_help
        exit 0
        ;;
esac


#-------------------------------------------------------------------------------
# require .commands file from here

if [ ! -f "$COMMANDS_FILE" ]; then
    echo -e "\033[32mCommands file not found\033[0m"
    exit 1
fi

# fallback: treat as generic action from .commands
RAW_COMMAND=$(grep "$ACTION\s*\=" "$COMMANDS_FILE" | cut -d "'" -f 2)

if [ -z "$RAW_COMMAND" ]; then
    echo -e "\033[31mUnknown action: $ACTION\033[0m"
    exit 1
fi

# substitute $@ placeholder if present, otherwise append args
if [[ "$RAW_COMMAND" == *'$@'* ]]; then
    COMMAND="${RAW_COMMAND//\$@/$*}"
else
    COMMAND="$RAW_COMMAND $*"
fi

echo -e "\033[34m> $COMMAND\033[0m"
eval "$COMMAND"
