#extract is a function
extract () 
{ 
    local verbose=0;
    local target_dir=".";
    local list_only=0;
    local args=();
    local exit_code=0;
    function _usage () 
    { 
        cat <<EOF
Usage: extract [OPTIONS] <file1> [file2 ...]

Options:
  -v, --verbose	   Show detailed extraction output
  -d DIR, --dir DIR   Extract into target directory DIR (default: current directory)
  -l, --list		  List contents of archive(s) without extracting
  -h, --help		  Show this help message and exit

Behavior:
  - Does not overwrite existing files/directories; aborts extraction if conflict is found
  - Returns a non-zero exit code if any extraction fails
EOF

    };
    while [[ $# -gt 0 ]]; do
        case "$1" in 
            -v | --verbose)
                verbose=1;
                shift
            ;;
            -d | --dir)
                shift;
                if [[ -z "$1" ]]; then
                    echo "Error: Missing argument for -d|--dir";
                    return 1;
                fi;
                target_dir="$1";
                shift
            ;;
            -l | --list)
                list_only=1;
                shift
            ;;
            -h | --help)
                _usage;
                return 0
            ;;
            --)
                shift;
                break
            ;;
            -*)
                echo "Unknown option: $1";
                _usage;
                return 1
            ;;
            *)
                args+=("$1");
                shift
            ;;
        esac;
    done;
    args+=("$@");
    if [[ ${#args[@]} -eq 0 && $list_only -eq 0 ]]; then
        _usage;
        return 1;
    fi;
    mkdir -p "$target_dir";
    function _need () 
    { 
        if ! command -v "$1" &> /dev/null; then
            echo "Error: Required tool '$1' is not installed. Skipping.";
            exit_code=1;
            return 1;
        fi
    };
    function _exists_conflict () 
    { 
        local path="$1";
        if [[ -e "$path" ]]; then
            echo "Error: '$path' already exists (will not overwrite).";
            exit_code=1;
            return 0;
        fi;
        return 1
    };
    for file in "${args[@]}";
    do
        if [[ ! -f "$file" ]]; then
            echo "Error: '$file' is not a valid file!";
            exit_code=1;
            continue;
        fi;
        if [[ $list_only -eq 1 ]]; then
            echo "Listing contents of: $file";
        else
            echo "Extracting: $file → $target_dir";
        fi;
        case "$file" in 
            *.tar.bz2 | *.tbz2)
                _need tar || continue;
                if [[ $list_only -eq 1 ]]; then
                    tar tjf "$file";
                else
                    tar -C "$target_dir" --keep-old-files $([[ $verbose -eq 1 ]] && echo "xvjf" || echo "xjf") "$file";
                fi || exit_code=1
            ;;
            *.tar.gz | *.tgz)
                _need tar || continue;
                if [[ $list_only -eq 1 ]]; then
                    tar tzf "$file";
                else
                    tar -C "$target_dir" --keep-old-files $([[ $verbose -eq 1 ]] && echo "xvzf" || echo "xzf") "$file";
                fi || exit_code=1
            ;;
            *.tar.xz)
                _need tar || continue;
                if [[ $list_only -eq 1 ]]; then
                    tar tJf "$file";
                else
                    tar -C "$target_dir" --keep-old-files $([[ $verbose -eq 1 ]] && echo "-xvf" || echo "-xf") "$file";
                fi || exit_code=1
            ;;
            *.tar)
                _need tar || continue;
                if [[ $list_only -eq 1 ]]; then
                    tar tf "$file";
                else
                    tar -C "$target_dir" --keep-old-files $([[ $verbose -eq 1 ]] && echo "xvf" || echo "xf") "$file";
                fi || exit_code=1
            ;;
            *.bz2)
                _need bunzip2 || continue;
                if [[ $list_only -eq 1 ]]; then
                    echo "Would decompress: $(basename "$file" .bz2)";
                else
                    local out="$target_dir/$(basename "${file%.bz2}")";
                    if [[ -e "$out" ]]; then
                        echo "Error: '$out' already exists.";
                        exit_code=1;
                        continue;
                    fi;
                    cp "$file" "$target_dir/";
                    ( cd "$target_dir" && bunzip2 "$(basename "$file")" );
                fi || exit_code=1
            ;;
            *.gz)
                _need gunzip || continue;
                if [[ $list_only -eq 1 ]]; then
                    echo "Would decompress: $(basename "$file" .gz)";
                else
                    local out="$target_dir/$(basename "${file%.gz}")";
                    if [[ -e "$out" ]]; then
                        echo "Error: '$out' already exists.";
                        exit_code=1;
                        continue;
                    fi;
                    cp "$file" "$target_dir/";
                    ( cd "$target_dir" && gunzip "$(basename "$file")" );
                fi || exit_code=1
            ;;
            *.rar)
                local unrar_bin;
                unrar_bin=$(command -v unrar || true);
                if [[ -n "$unrar_bin" ]]; then
                    _need unrar || continue;
                    if [[ $list_only -eq 1 ]]; then
                        unrar l "$file";
                    else
                        ( cd "$target_dir" && unrar x -o- "$file" );
                    fi;
                else
                    _need 7z || continue;
                    if [[ $list_only -eq 1 ]]; then
                        7z l "$file";
                    else
                        ( cd "$target_dir" && 7z x -aos "$file" $([[ $verbose -eq 0 ]] && echo "-y -bsp0 -bso0") );
                    fi;
                fi || exit_code=1
            ;;
            *.zip)
                _need unzip || continue;
                if [[ $list_only -eq 1 ]]; then
                    unzip -l "$file";
                else
                    _need zipinfo || continue;
                    local count;
                    count=$(zipinfo -1 "$file" | awk -F/ '{print $1}' | sort -u | wc -l);
                    if [[ "$count" -gt 1 ]]; then
                        local dir="$target_dir/${file%*.zip}";
                        if [[ -d "$dir" ]]; then
                            echo "Error: directory '$dir' already exists.";
                            exit_code=1;
                            continue;
                        fi;
                        echo "Creating directory: $dir";
                        unzip -n $([[ $verbose -eq 1 ]] && echo "" || echo "-q") -d "$dir" "$file";
                    else
                        ( cd "$target_dir" && unzip -n $([[ $verbose -eq 1 ]] && echo "" || echo "-q") "$file" );
                    fi;
                fi || exit_code=1
            ;;
            *.7z | *.zip.[0-9]* | '')
                _need 7z || continue;
                if [[ $list_only -eq 1 ]]; then
                    7z l "$file";
                else
                    ( cd "$target_dir" && 7z x -aos "$file" $([[ $verbose -eq 0 ]] && echo "-y -bsp0 -bso0") );
                fi || exit_code=1
            ;;
            *.Z)
                _need uncompress || continue;
                if [[ $list_only -eq 1 ]]; then
                    echo "Would uncompress: $(basename "$file" .Z)";
                else
                    local out="$target_dir/$(basename "${file%.Z}")";
                    if [[ -e "$out" ]]; then
                        echo "Error: '$out' already exists.";
                        exit_code=1;
                        continue;
                    fi;
                    cp "$file" "$target_dir/";
                    ( cd "$target_dir" && uncompress "$(basename "$file")" );
                fi || exit_code=1
            ;;
            *)
                echo "Warning: '$file' cannot be extracted";
                exit_code=1
            ;;
        esac;
        [[ $list_only -eq 1 ]] && echo "Listed: $file" || echo "Done: $file";
        echo;
    done;
    return $exit_code
}

extract $@
