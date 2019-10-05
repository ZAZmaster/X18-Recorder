#!/bin/bash

# Called from Autorecord.sh

RECORDING_HOME=$1
SOUND_DEVICE=$2
TRACKS=$3

cleanup() {
    sync
    echo Recording to "$RECORDING_FILE" has ended.
}

exitR() {
    kill -TERM $ARECORD_PID > /dev/null 2>&1
    cleanup
    echo "$(date) Recording stopped by user"
    exit $?
}

trap exitR SIGINT SIGTERM

sleep 1

# Main loop, runs indefinitely
while true
do

    # Look for XR18, and wait until it is found/plugged in
    echo -n 'Looking for XR18... '
    # use grep to filter the output of arecord -L, returns 0 (true) if found
    until arecord -L | grep "CARD=$SOUND_DEVICE" > /dev/null
    do
        sleep 1
    done
    echo 'Found XR18!'

    # Wait until it Hard Drive is plugged in
    echo -n 'Looking for Hard Drive... '
    # -e for "entry" exists in the filesystem (could be anything: file, directory, etc.)
    until [ -e "$RECORDING_HOME" ]
    do
        sleep 1
    done
    echo 'Found Hard Drive'

    # Abort if drive has no write permission
    echo -n 'Looking for write permission... '
    # -w for file has write access
    if [ ! -w "$RECORDING_HOME" ]
    then
        echo 'No write permission on Hard Drive (if all else fails, run as root)'
        exit 1
    fi
    echo 'Hard Drive has write permission!'

    # Figure out where to record to
    COUNT=1
    # -d for directory exists
    while [ -d "$RECORDING_HOME/$COUNT" ]
    do
        COUNT=$(($COUNT+1))
    done
    RECORDING_FOLDER="$RECORDING_HOME/$COUNT"
    
    mkdir $RECORDING_FOLDER
    MKDIR_SUCCES=$?
    if [ "$MKDIR_SUCCES" -eq 1 ]
    then
        echo "Recording device full, waiting for new device..."
        while [ "$MKDIR_SUCCES" -eq 1 ]
        do
            mkdir $RECORDING_FOLDER > /dev/null 2>&1
            MKDIR_SUCCES=$?
            sleep 1
        done
        continue
    fi
    
    chmod 777 $RECORDING_FOLDER
    RECORDING_FILE="$RECORDING_FOLDER/all_tracks.raw"

    # Start recording
    #   - "2> >(ts -s >&2)" redirects stderr [2>] into ts's stdin [>(ts ...)] and then redirects ts's stdout back to the original stderr address [>&2]
    #   - ts itself adds a timestamp to the start of each line that it receives and prints it back out
    #     - The -s option is relative time to when that line was run
    echo "Recording to $RECORDING_FILE"
    arecord --duration=$REC_LENGTH --device=hw:CARD=$SOUND_DEVICE,DEV=0 --channels=$TRACKS --file-type=raw --format=S32_LE --rate=48000 --buffer-time=200000 > "$RECORDING_FILE" 2> >(ts -s >&2) &
    # $! references the process id of the last command, we save this to be able to shut down arecord later
    ARECORD_PID=$!
    echo "Current arecord PID: $ARECORD_PID"

    # Monitor the recording
    # see if it's still running (-0 doesn't send any signals, but does do the error checking)
    while kill -0 "$ARECORD_PID" > /dev/null 2>&1
    do
        # Force a filesystem sync every 1 second to keep the buffer small enough to write without missing samples
        sleep 1
        sync
    done

    cleanup
done
