#!/bin/bash

input=Sync/Dossiers/Prj/immediat
OPTIONS=()
IDS=(0)
COUNT=0

while IFS=: read -r id label
do
    COUNT=$[COUNT+1]
    OPTIONS+=($COUNT "$label")
    IDS+=("$id")
done < "$input"

cmd=(dialog --clear --menu "Choisir un projet" 15 45 5)
choices=$("${cmd[@]}" "${OPTIONS[@]}" 2>&1 >/dev/tty)
for choice in $choices
do
   enquete=${IDS[$choice]}
done

if [ -z "$enquete" ]; then
        echo "enquete vide"
        exit 1
else 
	echo $enquete
fi
