#!/usr/bin/env bash
# shellcheck disable=SC1090

# GINAvbs: A backup solution making use of the power of Git
# (c) 2016-2018 GINAvbs, LLC (https://erebos.xyz/)
# Easy to use backups for configurations, logs and sql files.

# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

# This program is initially designed for the Erebos Network.
# If you are neither of those make sure be warned that you use, copy and/or
# modify at your own risk.

# Futhermore it's not recommended to use GINAvbs with another shell than
# GNU bash version 4.4

# It is highly recommended to use set -eEuo pipefail for every setup script
set -o errexit  # Used to exit upon error, avoiding cascading errors
set -o errtrace # Activate traps to catch errors on exit
set -o pipefail # Unveils hidden failures
set -o nounset  # Exposes unset variables


#### SPECIAL FUNCTIONS #####
# Functions with the purpose of making coding more convinient and
# debugging a bit easier.
# Do not missunderstand "SPECIAL FUNCTIONS" as test functions.
#
# NOTE: SPECIAL FUNCTIONS start with three CAPS letter.
#
# IF YOU ARE AWARE OF A BETTER FORM OF NAMING FEEL FREE TO OPEN A ISSUE
# OTHERWISE PLEASE USE THIS AS A GUIDELINE FOR ANY COMMIT.

EOS_string(){
	# allows to store EOFs in strings
	IFS=$'\n' read -r -d '' $1 || true;
	return $?
} 2>/dev/null

######## GLOBAL VARIABLES AND ENVIRONMENT VARIABLES #########
# For better maintainability, we define all global variables at the top.
# This allows us to make changes at their defaults
# in one place and lowers the risk of dumb bugs.
#
# GLOBAL variables are all, written in CAPS
# LOCAL variables are all, starting with a underscore
#
# NOTE: Variables starting with double underscore are readonly
#
# IF YOU ARE AWARE OF A BETTER FORM OF NAMING FEEL FREE TO OPEN A ISSUE
# OTHERWISE PLEASE USE THIS AS A GUIDELINE FOR ANY COMMIT

source /etc/os-release # source os release environment variables

# SYSTEM / USER VARIABLES
readonly __DISTRO="${ID}" # get distro id from /etc/os-release
readonly __DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" # workdir
readonly __FILE="${__DIR}/$(basename "${BASH_SOURCE[0]}")" # self
readonly __BASE="$(basename ${__FILE})" # workdir/self
readonly __ROOT="$(cd "$(dirname "${__DIR}")" && pwd)" # homedir

# DEPENDENCY / LOGS VARIABLES
# GINAvbs has currently one dependency that needs to be installed
readonly __GINA_DEPS=(git)
# Location of installation logs
readonly __GINA_LOGS="${__DIR}/install.log"

# SETUP VARIABLES
# Define and set default for enviroment variables
REPOSITORY=${GINA_REPOSITORY:-""}
SSHKEY=${GINA_SSHKEY:-""}
HOST=${GINA_HOST:-""}
USER=${GINA_USER:-""}
PASSWORD=${GINA_PASSWORD:-""}

INTERVAL=${GINA_INTERVAL:-"weekly"}

# COLOR / FORMAT VARIABLES
# Set some colors because without it ain't no fun
COL_NC='\e[0m' # default color

COL_LIGHT_GREEN='\e[1;32m' # green
COL_LIGHT_RED='\e[1;31m' # red
COL_LIGHT_MAGENTA='\e[1;95m' # magenta

TICK="[${COL_LIGHT_GREEN}✓${COL_NC}]" # green thick
CROSS="[${COL_LIGHT_RED}✗${COL_NC}]" # red cross
INFO="[i]" # info sign

# shellcheck disable=SC2034
DONE="${COL_LIGHT_GREEN} done!${COL_NC}" # a small motivation ^^
OVER="\\r\\033[K" # back to line start

# Our temporary logo, will might be updated someday
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

# Licenceing, recommedations and warnings
EOS_string LICENSE <<-'EOS'
+ # This file is copyright under the latest version of the EUPL.
+ # Please see LICENSE file for your rights under this license.
+
+ # This Programm is initialy designt for the Erebos Network.
+ # If you are neider of those make sure be warned thet you use, copie and/or
+ # modify at your own risk.
+
+ # Futhermore it's not recommended to use GINAvbs with another shell than
+ # GNU bash version 4.4
+
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
EOS

# Manual, learn more on our github site
EOS_string MANPAGE <<-'EOS'
+ # Manual:
+
+ # -r --remote "exports to a remote repository"
+ # -s --sshkey "deploys a given sshkey"
+ # -d --delete "deletes local repo"
+ # -h --help "shows man page"
+
+ # really hope that helps you
+
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
EOS

# This line has decorative purpose only
EOS_string COOL_LINE <<-'EOS'
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
EOS

######## FUNCTIONS #########
# Functions that are part of the core functionality of GINAvbs
#
# FUNCTIONS are all, written in lowercase
#
# IF YOU ARE AWARE OF A BETTER FORM OF NAMING FEEL FREE TO OPEN A ISSUE
# OTHERWISE PLEASE USE THIS AS A GUIDELINE FOR ANY COMMIT

install() {
	# Install packages passed in via argument array
	declare -a _argArray1=(${!1})
	declare -a _installArray=("")

	# Debian based package install - debconf will download the entire package
	# list so we just create an array of packages not currently installed to
	# cut down on the amount of download traffic.

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
			# Installing Packages
			apk add --force ${_installArray[@]}
			# Cleaning cached files
			rm -rf /var/cache/apk/* /var/cache/distfiles/*

			# Placing cron job
			cat <<-'EOF' > /etc/periodic/${INTERVAL}/ginavbs.sh
				#!/usr/bin/env bash
				echo ""

				# Terminate on errors and output everything to >&2
				set -xe

				# Commit changes to remote repository
				git add .
				git commit -m "$(date) automated backup (ginavbs.sh)"
				git push --force origin master
			EOF

			chmod +x /etc/periodic/${INTERVAL}/ginavbs.sh

			exec "/usr/sbin/crond" "-f" &
		;;
		'arch'|'manjaro')
			# Installing Packages if started as root
			if [[ $(pacman -S --noconfirm ${_installArray[@]}) ]]; then
				# Cleaning cached files
				pacman -Scc --noconfirm

			# Installing if sudo is installed
			elif [[ $(sudo pacman -S --noconfirm ${_installArray[@]}) ]]; then
				# Cleaning cached files
				sudo pacman -Scc --noconfirm

			# Try again as root
			else
				echo "${INFO} retry as root again"
			fi
		;;
		'debian'|'ubuntu'|'mint'|'kali')
			# Installing Packages if started as root
			if [[ $(apt-get install ${_installArray[@]} -y) ]]; then
				# Cleaning cached files
				apt-get clean -y

			# Installing if sudo is installed
			elif [[ $(sudo apt-get install ${_installArray[@]} -y) ]]; then
				# Cleaning cached files
				sudo apt-get clean -y

			# Try again as root
			else
				echo "${INFO} retry as root again"
			fi
			;;
			*) return 1;;
			esac
	fi

	return $?
}

make_temporary_log() {
	# Create a random temporary file for the log
	TEMPLOG=$(mktemp /tmp/gina_temp.XXXXXX)
	# Open handle 3 for templog
	exec 3>"$TEMPLOG"
	# Delete templog, but allow for addressing via file handle
	# This lets us write to the log without having a temporary file on
	# the drive, which is meant to be a security measure so there is not a
	# lingering file on the drive during the install process
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

	return $?
}

# A function to clone a repo
make_repo() {
	# Display the message and use the color table to preface the message
	# with an "info" indicator
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

	# Always return $?? Not sure this is correct
	return $?
} 2>/dev/null


update_repo() {
	# Display the message and use the color table to preface the message with
	# an "info" indicator
	echo -ne "+ ${INFO} Update repository in ${__DIR}..."
	# delete everything in it so git can clone into it
	#rm -rf ${__DIR}/*
	# Stash any local commits as they conflict with our working code
	#git stash --all --quiet &> /dev/null || true # Okay for stash failure
	#git clean --quiet --force -d || true # Okay for already clean directory
	#git checkout ginavbs || true

	git add . || true
	git commit -m "$(date) GINA init (init.sh)" || true

	# Pull the latest commits from master
	git fetch origin || true

	# Pull from and merge with remote repository
	git pull --force \
			 --quiet \
			 --no-edit \
			 --strategy=recursive \
			 --strategy-option=theirs \
			 --allow-unrelated-histories\
			 origin master \
			 || true

	# Push to remote repository
	git push --force \
			 --quiet \
			 --set-upstream \
			 origin master \
			 || true

	# Clone the repo and return the return code from this command
	#git clone -q "${REPOSITORY}" "${__DIR}" &> /dev/null || return $?

	# Show a colored message showing it's status
	echo -e "${OVER}+ ${TICK} Update repository in ${__DIR}"

	# Always return $?? Not sure this is correct
	return $?
} 2>/dev/null

nuke_everything() {
	# I am pretty sure there is a better way
	# pls don't push this button

	north_korea_mode=enabled;

	# welp, all local informations will be destroyed
	return $?
} 2>/dev/null

manual(){
	# Prints manual
	echo -e "+${COL_LIGHT_GREEN}"
	echo -e "${COL_LIGHT_GREEN}${COOL_LINE}"
	echo -e "+"
	echo -e "${MANPAGE}"
	echo -e "${COL_NC}+"
	return $?
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

error_handler(){

	echo "+ # ERROR:"
	echo "+"

	case $1 in
	40) echo "+ Bad Request: This function needs at least one Argument!";;
	43) echo "+ Permission Denied: Please try again as root!";;
	44) echo "+ Not Found: Username and Password not found!";;
	51)    echo "+ Not Implemented: Please read the Manual, fool!";;
	*)  echo "+ Internal Error: Shit happens! Something has gone wrong.";;
	esac

	echo "+"
	echo "+ error_code $1"

	return $?
} 2>/dev/null

exit_handler(){
	# Copy the temp log file into final log location for storage
	#copy_to_install_log # TODO logging still doesn't working like expected
	local error_code=$?

	if [[ ${error_code} == 0 ]]; then
		echo -e "+"
		echo -e "${COL_LIGHT_MAGENTA}${COOL_LINE}"
		echo -e "+"
		echo "+ Thanks for using GINAvbs"
		echo -e "+"
		echo -e "${COOL_LINE}"
		return ${error_code};
	fi

	echo -e "+"
	echo -e "${COL_LIGHT_RED}${COOL_LINE}"
	echo -e "+"
	error_handler ${error_code}
	echo -e "+"
	echo -e "${COOL_LINE}"
	exit ${error_code}
} 2>/dev/null

######## ENTRYPOINT #########

main(){
	echo -e "${COL_LIGHT_MAGENTA}"
	echo -e "${LOGO}"
	echo -e "${COL_LIGHT_GREEN}+"
	echo -e "${LICENSE}"
	echo -e "${COL_NC}+"

	set -o xtrace

	# The optional parameters string starting with ':' for silent errors
	local -r _OPTS=':r:i:s:dh-:'
	local -r INVALID_OPTION=51
	local -r INVALID_ARGUMENT=40

	while builtin getopts -- ${_OPTS} opt "$@"; do
		case ${opt} in
		r)    REPOSITORY=${OPTARG}
		;;
		i)    INTERVAL=${OPTARG}
		;;
		s)    SSHKEY=${OPTARG}
		;;
		d)    nuke_everything
		;;
		h)    manual
			return $?
		;;
		:)     required_argument ${OPTARG} ${INVALID_ARGUMENT}
		;;
		*)    case "${OPTARG}" in
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
			delete)
				nuke_everything
				return $?
			;;
			help)
				manual
				return $?
			;;
			*)
				invalid_option ${OPTARG} ${INVALID_OPTION}
			;;
			esac
		;;
		esac
	done

	local _tmp=""

	# Strip protocol prefix
	REPOSITORY="${REPOSITORY#*://}"
	# Strip link
	_tmp="${REPOSITORY%%/*}"
	# Get host
	HOST="${_tmp#*@}"
	# Strip host
	_tmp="${_tmp%%@*}"
	# Get username
	USER="${_tmp%%:*}"
	# Get password
	PASSWORD="${_tmp#*:}"

	if [[ ${USER} == ${PASSWORD} ]] && ! [[ ${SSHKEY} ]]; then
		# Check if no username or password and/or sshkey was added
		return 44
	fi

	# Install packages used by this installation script
	install __GINA_DEPS[@]

	if ! $(is_repo) || ! [[ $(ls -A "${__DIR}" 2>/dev/null) ]]; then
		make_repo
	fi

	update_repo

	return $?
}

# Traps everything
trap exit_handler 0 1 2 3 13 15 # EXIT HUP INT QUIT PIPE TERM

make_temporary_log

main "$@" 3>&1 1>&2 2>&3

exit 0
