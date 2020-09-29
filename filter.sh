#!/bin/bash

dbDirectory="/history/filefilter"
quarantineDirectory="/quarantine"
credentialsFile="filter.json"
declare -a searchDirectories=$(echo -n '(';jq '.file_filtering|.[]|.search_directory' $dbDirectory'/'$credentialsFile;echo -n ')')

for searchDirectory in "${searchDirectories[@]}"
do
	echo $searchDirectory
	declare -a directoryExceptions=$(echo -n '(';jq '.file_filtering|.[]|select(.search_directory=="'"$searchDirectory"'")|.directory_exceptions|.[]' $dbDirectory'/'$credentialsFile;echo -n ')')
	bannedFormats=$(jq -r '.file_filtering|.[]|select(.search_directory=="'"$searchDirectory"'")|.banned_format|.[]' $dbDirectory'/'$credentialsFile)
	
	policyName=$(jq -r '.file_filtering|.[]|select(.search_directory=="'"$searchDirectory"'")|.snapshot_name' $dbDirectory'/'$credentialsFile)
	qq snapshot_create_snapshot --name $policyName -t "7days" --path "$searchDirectory"
	snapshots=($(qq snapshot_list_snapshots --all| jq '.entries|.[]|select(.name=="'$policyName'")|.id'|tail -n 2))
	
	declare -a createdFiles=$(echo -n '(';qq snapshot_diff --newer-snapshot ${snapshots[1]} --older-snapshot ${snapshots[0]}|jq '.entries|.[]|select (.op=="CREATE")|.path';echo -n ')')
	for createdFile in "${createdFiles[@]}"
	do
		fileType=$(qq fs_file_get_attr --path "$createdFile"|jq -r '.type')
		
		if [[ $fileType == "FS_FILE_TYPE_DIRECTORY" ]]
		then
			for format in ${bannedFormats[@]}
			do
				declare -a filesInNewDirectory=$(echo -n '(';qq fs_walk_tree --path "$createdFile" --file-only |jq '.tree_nodes|.[]|.path';echo -n ')')
				
				for fileInNewDirectory in "${filesInNewDirectory[@]}"
				do
					fileInNewDirectoryLow="${fileInNewDirectory,,}"

                                if [[ "${fileInNewDirectoryLow##*.}" == "$format" ]]
                                then
                                        bannedFile="$fileInNewDirectory"

						exceptedDirectoryFile="0"
					####
					if [[ -n "$directoryExceptions" ]]
					then
					
						for exceptedDirectory in "${directoryExceptions[@]}"
						do
							echo $exceptedDirectory
							if [[ "$bannedFile" == "$exceptedDirectory"* ]]
							then
								exceptedDirectoryFile="1"
							fi
						done
					fi
					
					if [[ $exceptedDirectoryFile == "0" ]]
					then
						newMainDirectory="$quarantineDirectory"
						
						declare -a newDirectoryPath=$(echo -n '(';echo -n  "$bannedFile"|awk 'BEGIN{res=""; FS="/";}{ for(i=2;i<=NF-1;i++) {print "\""$i"\""}}';echo -n ')')
						
						for newDirectory in "${newDirectoryPath[@]}"
						do
							checkPath="$newMainDirectory"/"$newDirectory"
							fileID=$(qq fs_read_dir --path "$checkPath"|jq -r '.id')
							
							if ! [[ $fileID =~ ^[0-9]+$ ]] 
							then
								qq fs_create_dir --path "$newMainDirectory" --name "$newDirectory"
							fi
							newMainDirectory="$newMainDirectory"/"$newDirectory"
						done
						
						#bannedFileOwner=$(qq ad_sid_to_username --sid $(qq fs_file_get_attr --path "$bannedFile"|jq '.owner_details|.id_value'))

						echo "$bannedFile"
						qq fs_copy "$bannedFile" "$quarantineDirectory"/"$bannedFile"
						echo $(date)','"$bannedFile"','"$newMainDirectory" >> $dbDirectory/filefilter.log
						
						bannedFileId=$(qq fs_file_get_attr --path "$bannedFile"|jq -r '.id')
						qq fs_delete --id $bannedFileId

					else
						echo $(date)','"$bannedFile" "sits in a excepted directory"  >> $dbDirectory/filefilter.log
					fi
				fi
				done
			done
		elif [[ $fileType == "FS_FILE_TYPE_FILE" ]]
		then
			for format in ${bannedFormats[@]}
			do
			
				createdFileLow="${createdFile,,}"

				if [[ "${createdFileLow##*.}" == "$format" ]]
				then
					bannedFile="$createdFile"	
					
					exceptedDirectoryFile="0"
				####
					 if [[ -n "$directoryExceptions" ]]
                                        then	
					for exceptedDirectory in "${directoryExceptions[@]}"
					do
						if [[ "$bannedFile" == "$exceptedDirectory"* ]]
						then
							exceptedDirectoryFile="1"
						fi
					done
					fi
					
					if [[ $exceptedDirectoryFile == "0" ]]
					then
						newMainDirectory="$quarantineDirectory"
						
						declare -a newDirectoryPath=$(echo -n '(';echo -n  "$bannedFile"|awk 'BEGIN{res=""; FS="/";}{ for(i=2;i<=NF-1;i++) {print "\""$i"\""}}';echo -n ')')
						
						for newDirectory in "${newDirectoryPath[@]}"
						do
							checkPath="$newMainDirectory"/"$newDirectory"
							fileID=$(qq fs_read_dir --path "$checkPath"|jq -r '.id')
							
							if ! [[ $fileID =~ ^[0-9]+$ ]]
							then
								qq fs_create_dir --path "$newMainDirectory" --name "$newDirectory"
							fi
							newMainDirectory="$newMainDirectory"/"$newDirectory"
						done
						
						#bannedFileOwner=$(qq ad_sid_to_username --sid $(qq fs_file_get_attr --path "$bannedFile"|jq -r '.owner_details|.id_value'))
						
						echo "$bannedFile"
						qq fs_copy "$bannedFile" "$quarantineDirectory"/"$bannedFile"
						echo $(date)','"$bannedFile"','"$newMainDirectory" >> $dbDirectory/filefilter.log

						bannedFileId=$(qq fs_file_get_attr --path "$bannedFile"|jq -r '.id')
                                                qq fs_delete --id $bannedFileId

					else
						echo $(date)','"$bannedFile" "sits in a excepted directory"  >> $dbDirectory/filefilter.log
					fi
				fi
			done
		fi
	done
done
