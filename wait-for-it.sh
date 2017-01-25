#!/usr/bin/env bash
#   Use this script to test if a given TCP host/port are available

cmdname=$(basename $0)

echoerr() { if [[ $QUIET -ne 1 ]]; then echo "$@" 1>&2; fi }

usage()
{
    cat << USAGE >&2
Usage:
    $cmdname host:port [host:port...] [-s] [-t timeout] [-- command args]
    -s | --strict               Only execute subcommand if the test succeeds
    -q | --quiet                Don\'t output any status messages
    -t TIMEOUT | --timeout=TIMEOUT
                                Timeout in seconds, zero for no timeout
    -- COMMAND ARGS             Execute command with args after the test finishes
USAGE
    exit 1
}

wait_for()
{
    if [[ $TIMEOUT -gt 0 ]]; then
        echoerr "$cmdname: waiting $TIMEOUT seconds for $HOST:$PORT"
    else
        echoerr "$cmdname: waiting for $HOST:$PORT without a timeout"
    fi
    start_ts=$(date +%s)
    while :
    do
        (echo > /dev/tcp/$HOST/$PORT) >/dev/null 2>&1
        result=$?
        if [[ $result -eq 0 ]]; then
            end_ts=$(date +%s)
            echoerr "$cmdname: $HOST:$PORT is available after $((end_ts - start_ts)) seconds"
            break
        fi
        sleep 1
    done
    return $result
}

wait_for_wrapper()
{
    # In order to support SIGINT during timeout: http://unix.stackexchange.com/a/57692
    if [[ $QUIET -eq 1 ]]; then
        timeout $TIMEOUT $0 $HOST:$PORT --quiet --child --timeout=$TIMEOUT &
    else
        timeout $TIMEOUT $0 $HOST:$PORT --child --timeout=$TIMEOUT &
    fi
    PID=$!
    trap "kill -INT -$PID" INT
    wait $PID
    RESULT=$?
    if [[ $RESULT -ne 0 ]]; then
        echoerr "$cmdname: timeout occurred after waiting $TIMEOUT seconds for $HOST:$PORT"
    fi
    return $RESULT
}

declare -a HOSTS
declare -a PORTS
I=0

# process arguments
while [[ $# -gt 0 ]]
do
    case "$1" in
        *:* )
        hostport=(${1//:/ })
        I=$((I + 1))
        HOSTS[I]=${hostport[0]}
        PORTS[I]=${hostport[1]}
        shift 1
        ;;
        --child)
        CHILD=1
        shift 1
        ;;
        -q | --quiet)
        QUIET=1
        PARAMS="$PARAMS --quiet"
        shift 1
        ;;
        -s | --strict)
        STRICT=1
        shift 1
        ;;
        -t)
        TIMEOUT="$2"
        PARAMS="$PARAMS -t $2"
        if [[ $TIMEOUT == "" ]]; then break; fi
        shift 2
        ;;
        --timeout=*)
        PARAMS="$PARAMS -t ${1#*=}"
        TIMEOUT="${1#*=}"
        shift 1
        ;;
        --)
        shift
        CLI="$@"
        break
        ;;
        --help)
        usage
        ;;
        *)
        echoerr "Unknown argument: $1"
        usage
        ;;
    esac
done

hLen=${#HOSTS[@]}

if [[ hLen -eq 0 ]]; then
    echoerr "Error 1: you need to provide at least one host and port to test."
    usage
    exit
fi

if [[ hLen -eq 1 ]]; then
    #just the one value: process it
    HOST=${HOSTS[1]}
    PORT=${PORTS[1]}

    if [[ "$HOST" == "" || "$PORT" == "" ]]; then
        echoerr "Error 2: you need to provide a host and port to test."
        usage
    fi

    TIMEOUT=${TIMEOUT:-15}
    STRICT=${STRICT:-0}
    CHILD=${CHILD:-0}
    QUIET=${QUIET:-0}

    if [[ $CHILD -gt 0 ]]; then
        wait_for
        RESULT=$?
    else
        if [[ $TIMEOUT -gt 0 ]]; then
            wait_for_wrapper
            RESULT=$?
        else
            wait_for
            RESULT=$?
        fi
    fi
else
    #multiple values: split out to be processed
    for i in "${!HOSTS[@]}"; do
        HOST=${HOSTS[$i]}
        PORT=${PORTS[$i]}
        $0 $HOST:$PORT $PARAMS &
    done

    for job in `jobs -p`
    do
        wait $job || let "RESULT=1"
    done
fi

#finally, run (or not) the command and exit.
if [[ $CLI != "" ]]; then
    if [[ $RESULT -ne 0 && $STRICT -eq 1 ]]; then
        echo "$cmdname timedout/failed in strict mode, refusing to execute subprocess"
        exit 1
    fi
    exec $CLI
else
    exit $RESULT
fi