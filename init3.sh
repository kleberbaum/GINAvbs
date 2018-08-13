#!/usr/bin/env bash
# shellcheck disable=SC1090

# GINAvbs: A backup solution making use of the power of Git
# (c) 2017-2018 GINAvbs, LLC (https://erebos.xyz/)
# Easy to use backups for configurations, logs and sql.

# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

# This Programm is initialy designt for script kiddys and lazy network admins.
# Use at your own risk.

set -o errexit  # Used to exit upon error, avoiding cascading errors
set -o errtrace # Activate traps
set -o pipefail # Unveils hidden failures
set -o nounset  # Exposes unset variables

#### SPECIAL FUNCTIONS #####
# Functions that serve the purpos of makeing codeing more convinient
#
# SPECIAL FUNCTIONS start with a CAPS part
#
# IF YOU ARE AWARE OF A BETTER FORM OF NAMING FEEL FREE TO OPEN A ISSUE
# OTHERWISE PLEASE USE THIS AS A GUIDLINE FOR ANY COMMIT

EOS_string(){
	str='\n' read -r -d '' $1 || true;
	return 0
} 2>/dev/null

######## VARIABLES #########
# For better maintainability, we define the most impotant variables at the top.
# This allows us to make a change in one place and lowers the risk of dumb bugs.
#
# GLOBAL variables are all, written in CAPS
# LOCAL variables are all, starting with a underscore
#
# Variables starting with double underscore are readonly
#
# IF YOU ARE AWARE OF A BETTER FORM OF NAMING FEEL FREE TO OPEN A ISSUE
# OTHERWISE PLEASE USE THIS AS A GUIDLINE FOR ANY COMMIT

source /etc/os-release

readonly __DISTRO="${ID}"
readonly __DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly __FILE="${__DIR}/$(basename "${BASH_SOURCE[0]}")"
readonly __BASE="$(basename ${__FILE})"
readonly __ROOT="$(cd "$(dirname "${__DIR}")" && pwd)"

# GINAvbs has some dependencies that need to be installed
readonly __GINA_DEPS=(git)
# Location of installation logs
readonly __GINA_LOGS="${__DIR}/install.log"

# Check if any environment variables are set
REPOSITORY=${GINA_REPOSITORY:-""}
SSHKEY=${GINA_SSHKEY:-""}
HOST=${GINA_HOST:-""}
USER=${GINA_USER:-""}
PASSWORD=${GINA_PASSWORD:-""}

INTERVAL=${GINA_INTERVAL:-"weekly"}

# Set some colors couse without ain't no fun
COL_NC='\e[0m' # No Color
COL_LIGHT_GREEN='\e[1;32m'
COL_LIGHT_RED='\e[1;31m'
COL_LIGHT_MAGENTA='\e[1;95m'
TICK="[${COL_LIGHT_GREEN}✓${COL_NC}]"
CROSS="[${COL_LIGHT_RED}✗${COL_NC}]"
INFO="[i]"
# shellcheck disable=SC2034
DONE="${COL_LIGHT_GREEN} done!${COL_NC}"
OVER="\\r\\033[K"

EOS_string LOGO <<-'EOS'
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
+                      ___________   _____        __                           +
+                     / ____/  _/ | / /   |_   __/ /_  _____                   +
+                    / / __ / //  |/ / /| | | / / __ \/ ___/                   +
+                   / /_/ // // /|  / ___ | |/ / /_/ (__  )                    +
+                   \____/___/_/ |_/_/  |_|___/_.___/____/                     +
+                                                                              +
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
EOS

EOS_string LICENSE <<-'EOS'
+ # GINAvbs: A backup solution making use of the power of Git
+ # (c) 2017-2018 GINAvbs, LLC (https://erebos.xyz/)
+ # Easy to use backups for configurations, logs and sql.
+
+ # This file is copyright under the latest version of the EUPL.
+ # Please see LICENSE file for your rights under this license.
+
+ # This Programm is initialy designt for script kiddys and lazy network admins.
+ # Use at your own risk.
+
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
EOS

EOS_string MANPAGE <<-'EOS'
+ # -e --export "exports to a remote repository"
+ # -i --import "imports from a remote repository"
+ # -s --sshkey "deploys a given sshkey"
+ # -d --delete "deletes local repo"
+
+ # really hope that helps you
+
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
EOS

EOS_string COOL_LINE <<-'EOS'
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
EOS

######## FUNCTIONS #########
# Functions that are part of the core functionality of GINAvbs
#
# FUNCTIONS are all, written in lowercase
#
# IF YOU ARE AWARE OF A BETTER FORM OF NAMING FEEL FREE TO OPEN A ISSUE
# OTHERWISE PLEASE USE THIS AS A GUIDLINE FOR ANY COMMIT

# normal funcrions

install() {
    # Install packages passed in via argument array
    declare -a _argArray1=(${!1})
    declare -a _installArray=("")

    # Debian based package install - debconf will download the entire package list
    # so we just create an array of packages not currently installed to cut down on the
    # amount of download traffic.

	# For each package,
	for i in "${_argArray1[@]}"; do
		echo -ne "+ ${INFO} Checking for ${i}..."
		if [[ $(which "${i}" 2>/dev/null) ]]; then
			echo -e "${OVER}+ ${TICK} Checking for ${i} (is installed)"
		else
			echo -e "${OVER}+ ${INFO} Checking for ${i} (will be installed)"
			_installArray+=("${i}")
		fi 2>/dev/null
	done

	if [[ ${_installArray[@]} ]]; then
		case ${__DISTRO} in
		'alpine')
			# installing
	    	apk add --force ${_installArray[@]}
			# and cleaning
			rm -rf /var/cache/apk/* /var/cache/distfiles/*

			cat <<-'EOF' > /etc/periodic/${INTERVAL}/ginavbs.sh
				#!/usr/bin/env bash

				git add .
				git commit -m "$(date) automated backup (ginavbs.sh)"
				git push --force origin master
			EOF

			chmod +x /etc/periodic/${INTERVAL}/ginavbs.sh

			exec "/usr/sbin/crond" "-f" &
		;;
		'arch'|'manjaro')
			# installing if started as root
			if [[ $(pacman -S --noconfirm ${_installArray[@]}) ]]; then
				# and cleaning
				pacman -Scc --noconfirm

			# installing if sudo is installed
			elif [[ $(sudo pacman -S --noconfirm ${_installArray[@]}) ]]; then
				# and cleaning
				sudo pacman -Scc --noconfirm

			# try again as root
			else
				echo "${INFO} retriy as root again"
			fi
		;;
		'debian'|'ubuntu'|'mint'|'kali')
			# installing if started as root
			if [[ $(apt-get install ${_installArray[@]} -y) ]]; then
				# and cleaning
				apt-get clean -y

			# installing if sudo is installed
			elif [[ $(sudo apt-get install ${_installArray[@]} -y) ]]; then
				# and cleaning
				sudo apt-get clean -y

			# try again as root
			else
				echo "${INFO} retriy as root again"
			fi
			;;
			*) return 1;;
			esac
	fi

	return 0
}

make_temporary_log() {
    # Create a random temporary file for the log
    TEMPLOG=$(mktemp /tmp/gina_temp.XXXXXX)
    # Open handle 3 for templog
    # https://stackoverflow.com/questions/18460186/writing-outputs-to-log-file-and-console
    exec 3>"$TEMPLOG"
    # Delete templog, but allow for addressing via file handle
    # This lets us write to the log without having a temporary file on the drive, which
    # is meant to be a security measure so there is not a lingering file on the drive during the install process
    rm -f "$TEMPLOG"
} 2>/dev/null

copy_to_install_log() {
    # Copy the contents of file descriptor 3 into the install log
    # Since we use color codes such as '\e[1;33m', they should be removed
    sed 's/\[[0-9;]\{1,5\}m//g' < /proc/$$/fd/3 > "${installLogLoc}"
} 2>/dev/null

# A function for checking if a folder is a git repository
is_repo() {
	if [[ -d "${__DIR}/.git" ]]; then
		echo true
	else
		echo false
	fi

	return 0
}

# A function to clone a repo
make_repo() {
    # Display the message and use the color table to preface the message with an "info" indicator
    echo -ne "+ ${INFO} Create repository in ${__DIR}..."

	# delete everything in it so git can clone into it
	#rm -rf ${__DIR}/*

	git init || true

	git remote add origin ${REPOSITORY} || true

	#git branch ginavbs || true

    # Clone the repo and return the return code from this command
    #git clone -q "${REPOSITORY}" "${__DIR}" &> /dev/null || return $?
    # Show a colored message showing it's status
    echo -e "${OVER}+ ${TICK} Create repository in ${__DIR}"
    # Always return 0? Not sure this is correct
    return 0
} 2>/dev/null

# We need to make sure the repos are up-to-date so we can effectively install Clean out the directory if it exists for git to clone into
update_repo() {
	# Display the message and use the color table to preface the message with an "info" indicator
	echo -ne "+ ${INFO} Update repository in ${__DIR}..."
	# delete everything in it so git can clone into it
	#rm -rf ${__DIR}/*
	# Stash any local commits as they conflict with our working code
    #git stash --all --quiet &> /dev/null || true # Okay for stash failure
    #git clean --quiet --force -d || true # Okay for already clean directory
	#git checkout ginavbs || true

	git add . || true
	git commit -m "$(date) GINA init (init.sh)" || true

	# Pull the latest commits
	git fetch origin || true

    git pull --force \
			 --quiet \
			 --no-edit \
			 --strategy=recursive \
			 --strategy-option=theirs \
			 --allow-unrelated-histories\
			 origin master \
			 || true

    # Show a completion message
	git push --force \
			 --quiet \
			 --set-upstream \
			 origin master \
			 || true

	# Clone the repo and return the return code from this command
	#git clone -q "${REPOSITORY}" "${__DIR}" &> /dev/null || return $?
	# Show a colored message showing it's status
	echo -e "${OVER}+ ${TICK} Update repository in ${__DIR}"
	# Always return 0? Not sure this is correct
	return 0
} 2>/dev/null

nuke_everything() {
	# I am pretty shure there is a better way
	# pls don't push this button

	north_korea_mode=enabled;

	# welp, all local informations will be removed
} 2>/dev/null

manual(){
	echo -e "+${COL_LIGHT_GREEN}"
	echo -e "${COL_LIGHT_GREEN}${COOL_LINE}"
	echo -e "+"
	echo -e "${MANPAGE}"
	echo -e "${COL_NC}+"
} 2>/dev/null

required_argument(){
	echo "required argument not found for option -$1" 1>/dev/null
	manual
	return $2
} 2>/dev/null

invalid_option(){
	echo "required argument not found for option --$1" 1>/dev/null
	manual
	return $2
} 2>/dev/null

exit_handler(){
	# Copy the temp log file into final log location for storage
	#copy_to_install_log # TODO logging still doesnt working like expected

	if [[ $? == 0 ]]; then
		echo -e "+"
		echo -e "${COL_LIGHT_MAGENTA}${COOL_LINE}"
		echo -e "+"
		echo "+ Thanks for useing GINAvbs"
		echo -e "+"
		echo -e "${COOL_LINE}"
		return 0;
	fi
	echo -e "+"
	echo -e "${COL_LIGHT_RED}${COOL_LINE}"
	echo -e "+"
	echo "+ shit happens!"
	echo "+ an error has occurred..."
	echo -e "+"
	echo -e "${COOL_LINE}"
	exit "${error_code}"
} 2>/dev/null

######## ENTRYPOINT #########

main(){
	echo -e "${COL_LIGHT_MAGENTA}"
	echo -e "${LOGO}"
	echo -e "${COL_LIGHT_GREEN}+"
	echo -e "${LICENSE}"
	echo -e "${COL_NC}+"

	set -o xtrace

	# the optional parameters string starting with ':' for silent errors snd h for help usage
    local -r _OPTS=':r:i:s:dh-:'
	local -r INVALID_OPTION=2
	local -r INVALID_ARGUMENT=3

	while builtin getopts -- ${_OPTS} opt "$@"; do
		case ${opt} in
		r)	REPOSITORY=${OPTARG}
		;;
		i)	INTERVAL=${OPTARG}
		;;
		s)	SSHKEY=${OPTARG}
		;;
		d)	nuke_everything
		;;
		h)	manual
			return 0
		;;
		:) 	required_argument ${OPTARG} ${INVALID_ARGUMENT}
		;;
		*)	case "${OPTARG}" in
			repository=*)
				REPOSITORY=${OPTARG#*=}
			;;
			repository)
				if ! [[ "${!OPTIND:-'-'}" =~ ^- ]]; then
					REPOSITORY=${!OPTIND};
				else
					required_argument ${OPTARG} ${INVALID_ARGUMENT}
				fi
				OPTIND=$(( ${OPTIND} + 1 ))
			;;
			interval=*)
				INTERVAL=${OPTARG#*=}
			;;
			interval)
				if ! [[ ${!OPTIND:-'-'} =~ ^- ]]; then
					INTERVAL=${!OPTIND};
				else
					required_argument ${OPTARG} ${INVALID_ARGUMENT}
				fi
				OPTIND=$(( ${OPTIND} + 1 ))
			;;
			sshkey=*)
				SSHKEY=${OPTARG#*=}
			;;
			sshkey)
				if ! [[ ${!OPTIND:-'-'} =~ ^- ]]; then
					SSHKEY=${!OPTIND};
				else
					required_argument ${OPTARG} ${INVALID_ARGUMENT}
				fi
				OPTIND=$(( ${OPTIND} + 1 ))
			;;
			*)
				invalid_option ${OPTARG} ${INVALID_OPTION}
			;;
			esac
		;;
		esac
	done

	local _tmp=""

	_tmp="${REPOSITORY#*://}"

	REPOSITORY="${_tmp%%/.*}.git"

	_tmp="${_tmp%%/*}"

	HOST="${_tmp#*@}"

	_tmp="${_tmp%%@*}"

	USER="${_tmp%%:*}"

	PASSWORD="${_tmp#*:}"

	if [[ ${USER} ]] && [[ ${PASSWORD} ]] || [[ ${SSHKEY} ]]; then
		# Install packages used by this installation script
		install __GINA_DEPS[@]

		if ! $(is_repo) || ! [[ $(ls -A "${__DIR}" 2>/dev/null) ]]; then
			make_repo
		fi

		update_repo
	else
		return 5
	fi

	return 0
}

trap exit_handler 0 1 2 3 13 15 # EXIT HUP INT QUIT PIPE TERM

make_temporary_log

main "$@" 3>&1 1>&2 2>&3

exit 0
