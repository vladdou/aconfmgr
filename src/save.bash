# save.bash

# This file contains the implementation of aconfmgr's 'save' command.

function AconfSave() {
	local config_save_target=$config_dir/99-unsorted.sh
	local modified=n

	AconfCompile

	LogEnter 'Saving configuration...\n'

	#
	# Packages
	#

	LogEnter 'Examining packages...\n'

	# Unknown packages (installed but not listed)

	local -a unknown_packages
	comm -13 <(PrintArray packages) <(PrintArray installed_packages) | mapfile -t unknown_packages

	if [[ ${#unknown_packages[@]} != 0 ]]
	then
		LogEnter 'Found %s unknown packages. Registering...\n' "$(Color G ${#unknown_packages[@]})"
		printf '\n\n# %s - Unknown packages\n\n\n' "$(date)" >> "$config_save_target"
		local package source
		printf '%s\n' "${unknown_packages[@]}" \
			| sort -t/ -k2,1 \
			| \
			while IFS=/ read -r source package
			do
				Log '%s (%s)...\r' "$(Color M "%q" "$package")" "$source"
				local description
				description=$("$source"_GetPackageDescription "$package")
				local switch
				case "$source" in
					pacman)
						switch= ;;
					aur)
						switch=' --foreign' ;;
					*)
						FatalError 'Unknown source: %q\n' "$source"
				esac
				printf 'AddPackage%s %q #%s\n' "$switch" "$package" "$description" >> "$config_save_target"
			done
		modified=y
		LogLeave
	fi

	# Missing packages (listed but not installed on current system)

	local -a missing_packages
	comm -23 <(PrintArray packages) <(PrintArray installed_packages) | mapfile -t missing_packages

	if [[ ${#missing_packages[@]} != 0 ]]
	then
		LogEnter 'Found %s missing packages. Un-registering.\n' "$(Color G ${#missing_packages[@]})"
		printf '\n\n# %s - Missing packages\n\n\n' "$(date)" >> "$config_save_target"
		local package source
		printf '%s\n' "${missing_packages[@]}" \
			| sort -t/ -k2,1 \
			| \
			while IFS=/ read -r source package
			do
				local switch
				case "$source" in
					pacman)
						switch= ;;
					aur)
						switch=' --foreign' ;;
					*)
						FatalError 'Unknown source: %q\n' "$source"
				esac
				printf 'RemovePackage%s %q\n' "$switch" "$package" >> "$config_save_target"
			done
		modified=y
		LogLeave
	fi

	LogLeave # Examining packages

	#
	# Emit files
	#

	LogEnter 'Registering files...\n'

	function PrintFileProps() {
		local file="$1"
		local prop
		local printed=n

		for prop in "${all_file_property_kinds[@]}"
		do
			local key="$file:$prop"
			if [[ -n "${system_file_props[$key]+x}" && ( -z "${output_file_props[$key]+x}" || "${system_file_props[$key]}" != "${output_file_props[$key]}" ) ]]
			then
				printf 'SetFileProperty %q %q %q\n' "$file" "$prop" "${system_file_props[$key]}" >> "$config_save_target"
				unset "output_file_props[\$key]"
				unset "system_file_props[\$key]"
				printed=y
			fi
		done

		if [[ $printed == y ]]
		then
			printf '\n' >> "$config_save_target"
		fi
	}

	# Don't emit redundant CreateDir lines
	local -A skip_dirs
	local file
	( Print0Array system_only_files ; Print0Array changed_files ) | \
		while read -r -d $'\0' file
		do
			local path=${file%/*}
			while [[ -n "$path" ]]
			do
				skip_dirs[$path]=y
				path=${path%/*}
			done
		done

	if [[ ${#system_only_files[@]} != 0 || ${#changed_files[@]} != 0 ]]
	then
		LogEnter 'Found %s new and %s changed files.\n' "$(Color G ${#system_only_files[@]})" "$(Color G ${#changed_files[@]})"
		printf '\n\n# %s - New files\n\n\n' "$(date)" >> "$config_save_target"
		( Print0Array system_only_files ; Print0Array changed_files ) | \
			while read -r -d $'\0' file
			do
				if [[ -n ${skip_dirs[$file]+x} ]]
				then
					continue
				fi

				local dir
				dir="$(dirname "$file")"
				mkdir --parents "$config_dir"/files/"$dir"

				local func args props suffix=''

				local system_file type
				system_file="$system_dir"/files/"$file"
				type=$(LC_ALL=C stat --format=%F "$system_file")
				if [[ "$type" == "symbolic link" ]]
				then
					func=CreateLink
					args=("$file" "$(readlink "$system_file")")
					props=(owner group)
				elif [[ "$type" == "directory" ]]
				then
					func=CreateDir
					args=("$file")
					props=(mode owner group)
				else
					local size
					size=$(LC_ALL=C stat --format=%s "$system_file")
					if [[ $size == 0 ]]
					then
						func=CreateFile
						suffix=' > /dev/null'
					else
						cp "$system_file" "$config_dir"/files/"$file"
						func=CopyFile
					fi
					args=("$file")
					props=(mode owner group)
				fi

				# Calculate the optional function parameters
				local prop
				for prop in "${props[@]}"
				do
					local key="$file:$prop"
					if [[ -n "${system_file_props[$key]+x}" && ( -z "${output_file_props[$key]+x}" || "${system_file_props[$key]}" != "${output_file_props[$key]}" ) ]]
					then
						args+=("${system_file_props[$key]}")
						unset "output_file_props[\$key]"
						unset "system_file_props[\$key]"
					else
						args+=('')
					fi
				done

				# Trim redundant blank parameters
				while [[ -z "${args[-1]}" ]]
				do
					unset args[${#args[@]}-1]
				done

				printf '%s%s%s\n' "$func" "$(printf ' %q' "${args[@]}")" "$suffix" >> "$config_save_target"

				PrintFileProps "$file"
			done
		modified=y
		LogLeave
	fi

	if [[ ${#config_only_files[@]} != 0 ]]
	then
		LogEnter 'Found %s extra files.\n' "$(Color G ${#config_only_files[@]})"
		printf '\n\n# %s - Extra files\n\n\n' "$(date)" >> "$config_save_target"
		local i
		for ((i=${#config_only_files[@]}-1; i>=0; i--))
		do
			file=${config_only_files[$i]}
			printf 'RemoveFile %q\n' "$file" >> "$config_save_target"
		done
		modified=y
		LogLeave
	fi

	LogLeave # Emit files

	#
	# Emit remaining file properties
	#

	LogEnter 'Registering file properties...\n'

	AconfCompareFileProps # Update data after PrintFileProps' unsets

	if [[ ${#system_only_file_props[@]} != 0 || ${#changed_file_props[@]} != 0 ]]
	then
		printf '\n\n# %s - New file properties\n\n\n' "$(date)" >> "$config_save_target"
		local key
		( ( Print0Array system_only_file_props ; Print0Array changed_file_props ) | sort --zero-terminated ) | \
			while read -r -d $'\0' key
			do
				printf 'SetFileProperty %q %q %q\n' "${key%:*}" "${key##*:}" "${system_file_props[$key]}" >> "$config_save_target"
			done
		modified=y
	fi

	if [[ ${#config_only_file_props[@]} != 0 ]]
	then
		printf '\n\n# %s - Extra file properties\n\n\n' "$(date)" >> "$config_save_target"
		local key
		( Print0Array config_only_file_props | sort --zero-terminated ) | \
			while read -r -d $'\0' key
			do
				printf 'SetFileProperty %q %q %q\n' "${key%:*}" "${key##*:}" '' >> "$config_save_target"
			done
		modified=y
	fi

	LogLeave # Registering file properties

	if [[ $modified == n ]]
	then
		LogLeave 'Done (%s).\n' "$(Color G "configuration unchanged")"
	else
		LogLeave 'Done (%s).\n' "$(Color Y "configuration changed")"
	fi
}

: # include in coverage
