#! /usr/bin/env bash
# edfig.sh -- Config file manager
# @annahri

FILE="$HOME/.config/configs.list"
CMD="${0##*/}"

declare -A configs

get() { cut -d= -f"$1" <<< "$2" | xargs; }

msg_error() { echo "$1" >&2 && exit "$2"; }

usage() {
    cat <<EOF >&2
Usage: $CMD [subcommand|config name]
  $CMD add vim "\$HOME/.vimrc"
  $CMD vim
  $CMD edit vim
  $CMD edit
  $CMD ls

Subcommands:
  add    Add new config file to list
  rm     Remove config file from list
  edit   Edit an entry
  ls     List all stored configs
  help   Print this

EOF
    exit
}

# Load configs
config_load() {
    while IFS= read -r line; do
        callname="$(get 1 "$line")"
        configdir="$(get 2 "$line")"
        configs[$callname]="$configdir"
    done < <(grep '^[^\s#]\+' "$FILE")
}

# Add config from command
config_add() {
    test "$#" -eq 0 && \
        msg_error "Usage: $CMD add name path" 8

    local name="$1"
    local path="$2"

    test -f "$path" || \
        msg_error "Not found: $path" 9

    echo -e "$name = \"$path\"" | tee -a "$FILE" > /dev/null || \
        msg_error "Cannot add new config." 7

    echo "New config has been added."
    exit
}

config_edit() {
    local name="$1"
    test -z "$name" && \
        $EDITOR "$FILE" && exit

    awk '{print $1}' "$FILE" | grep -qw "$name" || \
        msg_error "Config for $name not found in $FILE" 1

    tempfile=$(mktemp /tmp/config_XXXXXXX.tmp)
    linenum=$(grep -n "$name" "$FILE" | cut -d: -f1)

    cleanup() { rm -f "$tempfile"; }
    trap cleanup EXIT INT QUIT

    grep "$name" "$FILE" | tee "$tempfile" > /dev/null || \
        msg_error "Error ocurred." 2

    $EDITOR "$tempfile" || \
        msg_error "Error on $EDITOR. Aborting" 3

    raw="$(head -1 "$tempfile")"
    line="$(echo "$raw" | sed 's/"/\\"/g;s/\//\\\//g')"

    test "$raw" == "$(head -1 "$tempfile")" && \
        echo "No changes." >&2 && exit

    sed "${linenum}s/.*/$line/" "$FILE" | sponge "$FILE" || \
        msg_error "Error editing entry." 4

    echo "Successfully edited." >&2
    cleanup && \
        trap -- EXIT INT QUIT

    exit
}

config_rm() {
    local name="$1"
    test "$name" || \
        msg_error "What to remove?" 1

    line=$(awk -v name="$name" '$1 == name' "$FILE")

    test "$line" || \
        msg_error "Config for $name not found in $FILE" 1

    tempfile=$(mktemp /tmp/configs-XXXX.tmp)

    cleanup() { rm -f "$tempfile"; }
    trap cleanup EXIT INT QUIT

    tee "$tempfile" < "$FILE" > /dev/null || \
        msg_error "Unable to make temporary copy." 2


    grep -v "$line" "$tempfile" | tee "$FILE" > /dev/null || \
        msg_error "Unable to remove $name from list" 4

    echo "Successfully removed." >&2

    cleanup && \
        trap -- EXIT INT QUIT

    exit
}

config_list() {
    grep '^[^\s#]\+' "$FILE" | \
        sed 's/"//g' | \
        sort | \
        column -s= -t -o '|' -N "CONFIG NAME , PATH "

    exit
}

# Begin Script
test -z "$1" && \
    usage

case "$1" in
    add) shift; cmd="add" ;;
    rm) shift; cmd="rm" ;;
    edit) shift; cmd="edit" ;;
    ls) cmd="list";;
    help|-h|--help) usage;;
    *) name="$1" ;;
esac

test "$cmd" == "add"  && \
    config_add "$@"

test -s "$FILE" || \
    mgs_error "$FILE doesn't exist or is empty. Create it and add something first.\nExample: configname = /path/to/config" 13

test "$cmd" == "rm" && \
    config_rm "$@"

test "$cmd" == "edit" && \
    config_edit "$@"

test "$cmd" == "list" && \
    config_list

config_load

config_path="${configs[$name]}"
config_file="${config_path##*/}"
config_ext=".${config_file##*.}"

if test ."$config_file" == "$config_ext"; then
    config_tmp="$(mktemp /tmp/config-"$name"-XXXXX.tmp)"
else
    config_tmp="$(mktemp /tmp/config-"$name"-XXXXX.tmp"${config_ext}")"
fi

cleanup() { rm -f "$config_tmp"; }

trap cleanup EXIT QUIT INT

test -z "$config_path" && \
    msg_error "Config $name is not found in $FILE" 1

cp "$config_path" "$config_tmp" 2> /dev/null || \
    msg_error "Error copying temp file. Aborting" 10

$EDITOR "${config_tmp}"

diff "$config_tmp" "$config_path" &> /dev/null && \
    echo "No changes." >&2 && exit

tee "$config_path" < "$config_tmp" > /dev/null || \
    msg_error "Error ocurred." 11

echo "Saving changes." >&2

cleanup && exit
