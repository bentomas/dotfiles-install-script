#! /bin/bash

# example usage:
#     bash ~/path/to/script/install.sh --from=~/path/to/files --to=~ --changes

################################################################################
#### parse arguments
################################################################################

#### defaults

# output debugging information
DEBUG=0

# just check for differences, don't make any actual changes
DRY_RUN=0

# just check for differences, don't make any actual changes
PRINT_DIFFS=0

# whether or not to clean up after itself.  this will remove any downloaded files
# and old copies of dotfiles.  This tries to trash, if possible
CLEANUP=1

# install distination
DEST=

# where to get the files from
SRC=

# show colors in changes output
COLORS=1

# use symbolic links for copying over new files
SYMBOLIC=0

# filter files by this name
FILTER=''

# if you want to uninstall
ONLY_REMOVE=0

# parse the options
for i in "$@"; do
    case $i in
        -h|--help)
            echo "TODO"
            exit
            shift
            ;;
        --debug)
            DEBUG=1
            shift
            ;;
        --to=*)
            DEST="${i#*=}"
            shift
            ;;
        --from=*)
            SRC="${i#*=}"
            shift
            ;;
        --filter=*)
            FILTER="${i#*=}"
            shift
            ;;
        -d|--diff)
            PRINT_DIFFS=1
            shift
            ;;
        -c|--changes)
            DRY_RUN=1
            shift
            ;;
        --no-clean)
            CLEANUP=0
            shift
            ;;
        --no-color)
            COLORS=0
            shift
            ;;
        --symbolic)
            SYMBOLIC=1
            shift
            ;;
        --remove)
            ONLY_REMOVE=1
            shift
            ;;
        *)
            echo "unknown option: $i"
            exit
        ;;
    esac
done

if [ "$DEBUG" -ne 0 ]; then
    echo "debug:          $DEBUG"
    echo "diffs:          $PRINT_DIFFS"
    echo "dry run:        $DRY_RUN"
    echo "clean:          $CLEANUP"
    echo "dest:           $DEST"
    echo "src:            $SRC"
    echo "colors:         $COLORS"
    echo "symbolic links: $SYMBOLIC"
    echo "filter:         $FILTER"
    echo "only remove:    $ONLY_REMOVE"

    echo ''
fi

if [ "$PRINT_DIFFS" -ne 0 ]; then
    DRY_RUN=1
fi

################################################################################
#### check for commands we use
################################################################################

# try and find a suitable diff executable
DIFF_CMD=`which diff 2>&1`

# git diff has more readable output (that we're used to)
GIT_CMD=`which git 2>&1`
if [ "$GIT_CMD" != '' ]; then
    PRETTY_DIFF_CMD="$GIT_CMD --no-pager diff --minimal"
else
    PRETTY_DIFF_CMD="$DIFF_CMD"
fi

# try and find a suitable date executable
DATE_CMD=`which date 2>&1`

# try and find a trash command
TRASH_CMD=`which trash`

################################################################################
#### colors
################################################################################

if [ "$COLORS" -ne 0 ]; then
    CHANGED_COLOR='\033[0;33m'
    ADDED_COLOR='\033[0;32m'
    REMOVED_COLOR='\033[0;31m'
    NO_COLOR='\033[0m' # No Color]]'
else
    CHANGED_COLOR=''
    ADDED_COLOR=''
    REMOVED_COLOR=''
    NO_COLOR=''
fi

################################################################################
#### figure out locations
################################################################################

SRC=`eval echo ${SRC//>}`
DEST=`eval echo ${DEST//>}`

if [ "$DATE_CMD" != '' ]; then
    CURRENT_TIME=`$DATE_CMD "+%m-%d_%H-%M-%S"`
else
    CURRENT_TIME=""
fi
BACKUP_DEST="${SRC}/dotfiles_$CURRENT_TIME"

echo "src:          $SRC"
echo "backup:       $BACKUP_DEST"
echo "destination:  $DEST"

if [ ! -d "$SRC" ]; then
    echo ""
    echo "cannot find src folder"
    exit
fi

if [ ! -d "$DEST" ]; then
    echo ""
    echo "cannot find destination folder"
    exit
fi

if [ ! "$FILTER" = "" ]; then
    if [ -f "$SRC/$FILTER" ]; then
        # it's a file, do nothing
        nop_isfile=1
    elif [ -d "$SRC/$FILTER" ]; then
        # it's a directory
        case "$FILTER" in
            */)
                # already has a slash at the end, do nothing
                nop_hasslashalready=1
                ;;
            *)
                # add slash at end
                FILTER="$FILTER/"
                echo "doesn't have a slash"
                ;;
        esac
    else
        echo ""
        echo "cannot find file specified by filter: $FILTER"
        exit
    fi
    echo "filter:       $FILTER"
fi

################################################################################
#### list of files that we want to write to the home directory ####
################################################################################

OLDIFS="${IFS}"
IFS=$'\n'
index=0
while read line ; do
    srcfiles[$index]="${line}"
    index=$(($index+1))
done < <(find "${SRC}" -name '.git' -prune -o  -not -name 'install.sh' -not -path "${SRC}/.*" -print)
IFS="${OLDIFS}"

################################################################################
#### create a list of possible files we want to REMOVE from our destination ####
################################################################################

index=0

# start with a list of the files we installed last time
if [ -f $DEST/.config_files_installed ]; then
  while read line ; do
    remove_candidates[$index]="$line"
    index=$(($index+1))
  done < $DEST/.config_files_installed
fi

# then add in the current files
for filename in ${srcfiles[@]}; do
  if [ "${filename:${#SRC}+1}" != "" ]; then
    remove_candidates[$index]="${filename:${#SRC}+1}"
    index=$(($index+1))
  fi
done

# only do unique files:
remove_candidates=(`echo "${remove_candidates[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '`)

################################################################################
#### go through and test which files need to be removed ########################
################################################################################

changed_index=0
added_index=0
removed_index=0

for filename in ${remove_candidates[@]}; do
    if [ "$FILTER" = "" -o "$filename" != "${filename/$FILTER/}" ]; then
        #echo $filename

        # if the file already exists then we need to see if it changed
        if [ -f "$DEST/.$filename" ]; then
            if [  "$ONLY_REMOVE" -eq 0 -a -f "$SRC/$filename" ]; then
                # it still exists in the new files, check and see if it changed
                if [ "$DIFF_CMD" != '' ]; then
                    $DIFF_CMD "$DEST/.$filename" "$SRC/$filename" > /dev/null 2> /dev/null
                    different=$?
                else
                    different=1
                fi

                if [ "$different" != "0" ]; then
                    if [ "$PRINT_DIFFS" -ne 0 ]; then
                        echo ""
                        $PRETTY_DIFF_CMD "$DEST/.$filename" "$SRC/$filename" 2> /dev/null
                        #echo "end diff for $filename"
                    fi
                    #echo $DEST/.$filename "different from" $SRC/$filename
                    changed[$changed_index]="$filename"
                    changed_index=$(($changed_index+1))
                fi
            else
                # new source doesn't have it, so we need to remove it
                #echo "$DEST/.$filename removed"
                removed[$removed_index]="$filename"
                removed_index=$(($removed_index+1))
            fi
        elif [ -d "$DEST/.$filename" ]; then
            # do nothing
            nop=1
        elif [ -h "$DEST/.$filename" ]; then
            # the file exists but is a symbolic link that is broken, let's just
            # mark it for removal. (we know the link is broken because the -f and
            # -d tests above failed)
            removed[$removed_index]="$filename"
            removed_index=$(($removed_index+1))
        elif [ -f "$SRC/$filename" ]; then
            # new source has it, old doesn't, so we need to add it
            #echo "new file" $SRC/$filename
            added[$added_index]="$filename"
            added_index=$(($added_index+1))
        fi
    fi
done

have_changes=0

if [ "$changed_index" -ne 0 ]; then
    have_changes=1
fi
if [ "$added_index" -ne 0 ]; then
    have_changes=1
fi
if [ "$removed_index" -ne 0 ]; then
    have_changes=1
fi

if [ "$have_changes" -ne 0 ]; then
    echo ""
    echo "changes:"

    for filename in ${added[@]}; do
        echo -e "${ADDED_COLOR}+ $filename${NO_COLOR}"
    done

    for filename in ${removed[@]}; do
        echo -e "${REMOVED_COLOR}- $filename${NO_COLOR}"
    done

    for filename in ${changed[@]}; do
        echo -e "$CHANGED_COLOR~ $filename${NO_COLOR}"
    done
fi


if [ "$have_changes" -eq 0 ]; then
    echo ""
    echo "no changes necessary"
fi

################################################################################
#### actually go in and move the old files to the backup folder
################################################################################

if [ "$DRY_RUN" -eq 0 ]; then

    echo ""

    # instead of removing, we move the files from the destination to a tmp dir.
    # this serves two purposes, cleaning up our home directory for when we change
    # dotfiles, and also backing up every file we overwrite

    index=0
    for filename in ${changed[@]}; do
        to_remove[$index]="$filename"
        index=$(($index+1))
    done
    for filename in ${removed[@]}; do
        #echo $filename
        to_remove[$index]="$filename"
        index=$(($index+1))
    done

    for filename in ${to_remove[@]}; do
        dirname=( `dirname "$filename"` )

        #echo $filename

        # only make the $BACKUP_DEST folder if we have files to put in it
        if [ ! -d "$BACKUP_DEST" ]; then
            echo "backing up changed destination versions"
            mkdir -p "$BACKUP_DEST"
        fi

        # make sure the folder path exists in the $BACKUP_DEST folder
        if [ -d $DEST/.$dirname -a "$dirname" != "." -a ! -d  "$BACKUP_DEST/$dirname" ]; then
            mkdir -p "$BACKUP_DEST/$dirname"
        fi

        if [ "$DEBUG" -ne 0 ]; then
            echo ".$filename"
        fi

        #move the file
        mv "$DEST/.$filename" "$BACKUP_DEST/$filename"

        # don't leave empty directories
        if [ -d "$DEST/.$dirname" -a "$dirname" != "." ]; then
            # check to see if the folder is empty
            if [ "$(ls -A $DEST/.$dirname)" = "" ]; then
                #echo ".$dirname"
                #echo "rmdir \"$DEST/.$dirname\""
                rmdir "$DEST/.$dirname"
            fi
        fi
    done
fi

################################################################################
#### write new versions of files to destination
################################################################################

if [ "$DRY_RUN" -eq 0 ]; then
    if [ "$ONLY_REMOVE" -eq 0 ]; then
        has_outputted_copying=0

        mkdir -p "$DEST/"

        if [ -f "$DEST/.config_files_installed" ]; then
            rm "$DEST/.config_files_installed"
        fi

        # we're about to create a new list of the files, so start with a blank one
        touch "$DEST/.config_files_installed"

        for filename in ${srcfiles[@]}; do
            filename=${filename:${#SRC}+1}
            #echo $filename

            dirname=( `dirname "$filename"` )

            # make sure the file is a file and not a directory
            if [ -f "$SRC/$filename" ]; then
                # don't bother overwritting if the file already is there (because
                # it didn't change: we mv files that changed to the backup folder)
                if [ ! -f "$DEST/.$filename" ]; then
                    # only write this file if there isn't a filter, or if the file matches the filter
                    if [ "$FILTER" = "" -o "$filename" != "${filename/$FILTER/}" ]; then
                        if [ "$has_outputted_copying" -eq 0 ]; then
                            has_outputted_copying=1
                            echo "writing src versions"
                        fi
                        # make sure the directory exists for this file
                        if [ $dirname != '.' -a ! -d "$DEST/.$dirname" ]; then
                            if [ "$DEBUG" -ne 0 ]; then
                                echo ".$dirname"
                            fi
                            #echo "mkdir -p \"$DEST/.$dirname\""
                            mkdir -p "$DEST/.$dirname"
                        fi

                        if [ "$DEBUG" -ne 0 ]; then
                            echo ".$filename"
                        fi

                        if [ "$SYMBOLIC" -ne 0 ]; then
                            echo "ln -s \"$SRC/$filename\" \"$DEST/.$filename\""
                            ln -s "$SRC/$filename" "$DEST/.$filename"
                        else
                            #echo "cp \"$SRC/$filename\" \"$DEST/.$filename\""
                            cp "$SRC/$filename" "$DEST/.$filename"
                        fi
                    fi
                fi
                echo "$filename" >> $DEST/.config_files_installed
            elif [ -d "$SRC/$filename" ]; then
                # it isn't a file, it's a dir.  we skip dirs, as they'll get made
                # for actual files above, UNLESS we're doing a symbolic link install,
                # in which case we want to create the symbolic link for this folder
                if [ ! -d "$DEST/.$filename" ]; then
                    if [ "$SYMBOLIC" -ne 0 ]; then
                        echo "ln -s \"$SRC/$filename\" \"$DEST/.$filename\""
                        ln -s "$SRC/$filename" "$DEST/.$filename"
                    fi
                fi
                # either way, we want to keep track of this folder as being installed
                # so it can be removed if necessary
                echo "$filename" >> $DEST/.config_files_installed
            fi
        done
    else
        if [ "$DEBUG" -ne 0 ]; then
            echo "skipping writing new"
        fi
    fi
fi

################################################################################
#### cleanup
################################################################################

if [ "$CLEANUP" -ne 0 ]; then
    # trash the backup files
    if [ -e "$BACKUP_DEST/" ]; then
        echo "cleaning up backup"
        if [ "$DEBUG" -ne 0 ]; then
            echo "trashing '$BACKUP_DEST'"
        fi

        if [ -e "$TRASH_CMD" ]; then
          $TRASH_CMD "$BACKUP_DEST/"
        else
          echo "failed to clean backup because could not find a \`trash\` command"
        fi
    fi
else
    if [ "$DEBUG" -ne 0 ]; then
        echo "skipping cleanup"
    fi
fi
