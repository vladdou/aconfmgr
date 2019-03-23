# distros/debian.bash

# This file implements aconfmgr package management for apt-based distributions.

# APT=${APT:-apt}

# apt_opts=("$APT")
# aurman_opts=(aurman)
# pacaur_opts=(pacaur)
# yaourt_opts=(yaourt)
# yay_opts=(yay)
# makepkg_opts=(makepkg)

function apt_InstallPackages() {
	local asdeps=false
	if [[ "$1" == --asdeps ]]
	then
		asdeps=true
		shift
	fi

	local target_packages=("$@")
	sudo apt install "${target_packages[@]}"
	if $asdeps
	then
		debian_UnpinPackages "${target_packages[@]}"
	fi
}

function apt_GetPackageDescription() {
	local package=$1

	dpkg-query -f '${Description}\n' -W "$package" | head -1
}

function apt_GetPackagesInGroup() {
	local group=$1

	FatalError 'TODO\n'
}

function debian_GetAllPackagesFiles() {
	apt_GetInstalledPackages | xargs dpkg -L | grep '^/' | sort -u
}

function apt_GetInstalledPackages() {
	LC_ALL=C dpkg --get-selections | grep -v '\bdeinstall$' | cut -d $'\t' -f 1 | cut -d : -f 1
}

function apt_GetExplicitlyInstalledPackages() {
	apt-mark showmanual
}

function debian_GetPackageOwningFile() {
	local file=$1

	FatalError 'TODO\n'
}

function debian_HaveOrphanPackages() {
	LC_ALL=C apt-get -qs autoremove | grep -q 'The following packages will be REMOVED:'
}

function debian_PruneOrphanPackages() {
	sudo env LC_ALL=C apt-get autoremove
}

function debian_UnpinPackages() {
	local packages=("$@")

	sudo apt-mark auto "${packages[@]}"
}

function debian_PinPackages() {
	local packages=("$@")

	sudo apt-mark manual "${packages[@]}"
}

# Get the path to the package file (.deb) for the specified package.
# Download or build the package if necessary.
function debian_NeedPackageFile() {
	set -e
	local package="$1"

	FatalError 'TODO\n'
}

# Extract the original file from a package to stdout
function debian_GetPackageOriginalFile() {
	local package="$1" # Package to extract the file from
	local file="$2" # Absolute path to file in package

	FatalError 'TODO\n'
}

# Extract the original file from a package to a directory
function debian_ExtractPackageOriginalFile() {
	local archive="$1" # Path to the .pkg.tar.xz package to extract from
	local file="$2" # Path to the packaged file within the archive
	local target="$3" # Absolute path to the base directory to extract to

	FatalError 'TODO\n'
}

# function BashBugFunc() {
# 	echo 1 | \
# 		while read -r package
# 		do
# 			true | true
# 		done
# }
# function CheckBashBug() {
# 	BashBugFunc > /dev/null
# }
# CheckBashBug

# Lists modified files.
# Format: <package><TAB><prop><TAB><expected-value><TAB><path><NUL>
# <prop> can be one of owner, group, mode, data, deleted, and progress.
function debian_FindModifiedFiles() {
	AconfNeedProgram debsums debsums n 1>&2

	Log '%s: Debian/apt support is work-in-progress. File attributes (type, mode, owner, group) are not tracked.\n' "$(Color Y "Warning")"

	local package
	while read -r package
	do
		printf '%s\t%s\t%s\t%s\0' "$package" progress '' ''

		sudo env LC_ALL=C true debsums --list-missing -a "$package" 2>&1 | \
			while read -r line
			do
				if [[ $line =~ ^(.*[^\ ])\ *(OK|FAILED)$ ]]
				then
					local file="${BASH_REMATCH[1]}"
					local result="${BASH_REMATCH[2]}"

					if [[ "$result" == OK ]]
					then
						continue
					elif [[ "$result" == FAILED ]]
					then
						printf '%s\t%s\t%s\t%q\0' "$package" data - "$file"
					else
						Log 'Unknown debsums result%s\n' "$(Color Y "%q" "$result")"
					fi
				else
					Log 'Unknown debsums output line: %s\n' "$(Color Y "%q" "$line")"
				fi
			done
	done < <(apt_GetInstalledPackages) # use process substitution to work around bash bug
}

function apt_Apply_InstallPackages() {
	local packages=("$@")

	function Details() { Log 'Installing the following packages:%s\n' "$(Color M " %q" "${packages[@]}")" ; }
	Confirm Details

	apt_InstallPackages "${packages[@]}"
}

: # include in coverage
