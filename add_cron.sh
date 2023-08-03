#!/bin/bash

#arguments: 
# give minutes, hours, days or months
# and command will run when that time hits


#crontab syntax: "minutes hours dateofmonth month dayofweek command"
MINUTES=$1
HOURS=$2
DAY_OF_MONTH=$3
MONTH=$4
DOW=$5
COMMAN=$6
echo "Minutes: $MINUTES Hours: $HOURS DOM: $DAY_OF_MONTH MONTH: $MONTH command: $COMMAN"
echo $*
exit
if [[ -z $MINUTES ]] ;then
    printf " no interval specified\n"
elif [[ -z $HOURS ]] ;then
    printf " no interval specified2\n"
elif [[ -z $COMMAND ]] ;then
    printf " no command specified\n"
else
    CRONIN="/tmp/cti_tmp"
    crontab -l | grep -vw "$MINUTES $HOURS $DAY_OF_MONTH $MONTH \* $DOW" > "$CRONIN"
    echo "$MINUTES $HOURS $DAY_OF_MONTH $MONTH \* $COMMAND " >> $CRONIN
    crontab "$CRONIN"
    rm $CRONIN
fi
