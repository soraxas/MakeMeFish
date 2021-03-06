function mm --description "MakeMeFish - List all Make targets in the Makefile of the current directory"
    
    set current_pos 1 
    while test (count $argv) -ge $current_pos
        # Check if a help flag was passed to mm
        set help_flags -- -h --help
        if contains -- $argv[$current_pos] $help_flags
            echo ""
            echo "    Usage:"
            echo "      " (set_color green)"mm"(set_color normal) "will look for a Makefile in the order specified by GNU Make and list all targets in it."
            echo "      " "To filter for a specific target, just start typing and targets will be filtered as you type."
            echo "      " (set_color green)"mm <keyword>"(set_color normal) "will start MakeMeFish with an initial, editable query" (set_color green)"<keyword>"(set_color normal)
            echo "      " (set_color green)"mm -i"(set_color normal) "will start MakeMeFish in interactive mode. When a target is run, you will return to the selection menu."
            echo "      " (set_color green)"mm -f <filename>"(set_color normal) "to specify what Makefile to load."
            echo "      " "All flags can be combined in any order."
            echo ""
            return 0
        else if test $argv[$current_pos] = "-f" 
            set current_pos (math "$current_pos+1") # skip the next
            set filename $argv[$current_pos]
        else if test $argv[$current_pos] = "-i" 
            set interactive 1
        else
            if set -q initial_query
                set initial_query $initial_query $argv[$current_pos]
            else
                set initial_query $argv[$current_pos]
            end
        end
        set current_pos (math "$current_pos+1")
    end

    function __mm_get_makefile_name -a 'filename'
        if test -n "$filename"
            set makefile_filenames $filename
        else 
            set makefile_filenames 'GNUmakefile' 'makefile' 'Makefile'
        end
        for filename in $makefile_filenames 
            if test -f $filename
                echo $filename
                break
            end
        end
    end

    # Based on: 
    # https://github.com/fish-shell/fish-shell/blob/8e418f5205106b11f83fa1956076a9b20c56f0f9/share/completions/make.fish 
    # and 
    # https://stackoverflow.com/a/26339924
    function __mm_parse_makefile -a 'filename'
        # Ensure correct locale set
        set -lx LC_ALL C

        set makeflags -f $filename
        
        if make --version 2>/dev/null | string match -q 'GNU*'
            make $makeflags -pRrq : 2>/dev/null |
            awk -F: '/^# Files/,/^# Finished Make data base/ {
                        if ($1 == "# Not a target") skip = 1;
                        if ($1 !~ "^[#.\t]") { 
                            if (!skip) print $1; skip=0 
                        }
                    }' 2>/dev/null
        else
            # BSD make
            make $makeflags -d g1 -rn >/dev/null 2>| awk -F, '/^#\*\*\* Input graph:/,/^$/ {if ($1 !~ "^#... ") {gsub(/# /,"",$1); print $1}}' 2>/dev/null
        end
    end

    function __mm_get_targets -a 'filename'
        set static_targets
        set file_targets
        set generated_targets 
        
        set parsed_makefile (__mm_parse_makefile $filename | sort -f)
        for row in $parsed_makefile  # Loop over all rows in the Makefile
            set row (string trim $row)
            if test -n "$row"  # No blanks plz
                if test (string match -r '.\.|\/' $row)  # this is a file or path
                    set file_targets $file_targets $row
                else  # grep the target and see if it's generated by a function or a true target 
                    set found_in_file (grep "$row:" $filename)
                    if test -n "$found_in_file"
                        set static_targets $static_targets $row  # true target
                    else
                        set generated_targets $generated_targets $row  # generated by function
                    end
                end
            end
        end
    
        string split " " $static_targets $file_targets $generated_targets
    end

    function __mm_fzf_command -a 'filename' -a 'interactive' -a 'make_command' -a 'query'
        if [ $interactive -eq 1 ]
            set fzf_interactive "--bind \"enter:execute:$make_command {}; echo; echo 'Done'; sleep 1\""
        end

        if test -n "$query"
            set fzf_query "--query=$query"
        end
        set fzf_opts "--read0 
                      $fzf_query 
                      $fzf_interactive
                      --height 60% 
                      --layout=reverse 
                      --border 
                      --preview-window='right:60%' 
                      --preview='grep 
                      --color=always -A 10 -B 1 \^{}: $filename; or echo -GENERATED TARGET-'"
        
        set -q FZF_TMUX; or set FZF_TMUX 0
        set -q FZF_TMUX_HEIGHT; or set FZF_TMUX_HEIGHT 60%
        if [ $FZF_TMUX -eq 1 ]
            echo "fzf-tmux -d$FZF_TMUX_HEIGHT $fzf_opts"
        else
            echo "fzf $fzf_opts"
        end
    end

    set custom_filename $filename
    set filename (__mm_get_makefile_name $filename)
    if test -z "$filename"
        echo 'No makefile found in the current working directory'
    else
        set targets (__mm_get_targets $filename)
        if test -n "$targets"
            if test -n "$custom_filename"
                set make_command "make -f $filename"
            else
                set make_command "make"
            end
            # Interactive?
            if test -n "$interactive"; and test $interactive -eq 1   
                string join0 $targets | eval (__mm_fzf_command $filename 1 $make_command $initial_query)
            else
                string join0 $targets | eval (__mm_fzf_command $filename 0 $make_command $initial_query) | read -lz result  # print targets as a list, pipe them to fzf, put the chosen command in $result
                set result (string trim -- $result)  # Trim newlines and whitespace from the command
                and commandline -- "$make_command $result"  # Prepend the make command
                commandline -f repaint  # Repaint command line
            end
        else
            echo "No targets found in $filename"
        end
    end
end