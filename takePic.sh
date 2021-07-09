#!/bin/bash

OUTPUTDIR="/images"
SCRIPTSDIR="/root/picam"
DRIVEUUID="7309-DD8D"

LOGFILE="$SCRIPTSDIR/images.log"

SLEEPBETWEENPICS=300  ## note: delay will actually be this value plus the time it takes for the pi to boot and shutdown
INTERVAL=4 ## note: time between pictures in hours
RESTART=`date -d "+$INTERVAL hour" -Iseconds` ## time of the day to reboot after taking pic, based on interval

# latitude and longitude for your location
LAT="52.5811N"
LON="12.1955E"

mount -U $DRIVEUUID $OUTPUTDIR

# check to see if the script should run or not, based on the external switch position
echo "21" > /sys/class/gpio/export
echo "in" > /sys/class/gpio/gpio21/direction
sleep 1
SWITCH=`cat /sys/class/gpio/gpio21/value`
echo "21" > /sys/class/gpio/unexport

# if the switch is on, then exit and let the pi continue to operate
if [ "$SWITCH" -eq "1" ]; then
	exit
fi

# overwrite the original if there are any updates to the scripts on the USB
cp $OUTPUTDIR/scripts/takePic.sh $SCRIPTSDIR
cp $OUTPUTDIR/scripts/timediff.sh $SCRIPTSDIR



# time stuff to figure out restart times so pictures aren't taken over night
TOMORROW=`date -d "+1 day" +%d`
TOMORROW_RISE=`sunwait list rise -d $TOMORROW $LAT $LON`

RISESETSTRING=`sunwait list $LAT $LON`

# split the string into two separate elements, one for rise, one for set
IFS=', ' read -r -a TIMEARR <<< $RISESETSTRING
RISETIME="${TIMEARR[0]}"
SETTIME="${TIMEARR[1]}"
NOW=`date "+%H:%M"`

TOMORROW_RISE_ISO=`date -d"$TOMORROW_RISE" +"%Y-%m-%dT%H:%M:%S%:z"`


# time between now and sunset
SUNSETDIFF=`$SCRIPTSDIR/timediff.sh "$NOW" "$SETTIME"`

# if we'are more than 35 min after sunset, don't take another picture and sleep until sunrise
if [ $SUNSETDIFF -lt -1805 ]; # if 35min after sunset still take a picture
then
	# next picture should be after sunrise
	NOWTOMIDNIGHT=`$SCRIPTSDIR/timediff.sh "$NOW" "23:59:59"`
	MIDNIGHTTORISE=`$SCRIPTSDIR/timediff.sh "00:00:01" "$RISETIME"`
	SLEEPBETWEENPICS=$((NOWTOMIDNIGHT + MIDNIGHTTORISE))
    ACTION="NO picture taken"
	RESTART=$TOMORROW_RISE_ISO
else
    # take the picture
    ACTION="picture taken"
    DATE=$(date +"%Y-%m-%d_%H%M")
    raspistill -o "$OUTPUTDIR/image-$DATE.jpg" -ts --exif -ex=auto
fi

if [ $SUNSETDIFF -lt 12600 ];
    then RESTART=$TOMORROW_RISE_ISO # restart next day, if only less than 3.5hrs till sunset
fi

# write to log
echo "`date -Iminutes` - $ACTION, $SUNSETDIFF secs to sunset, sleep until: $RESTART" >> $LOGFILE

# next power up
# RESTART=`date -d "+$INTERVAL minute" -Iseconds` #for restart in 4min
echo "rtc_alarm_set $RESTART 127" | nc -q 0 127.0.0.1 8423
# shutdown
sudo shutdown -h 2
