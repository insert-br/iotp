#!/bin/bash

. ../utils.sh

TOTAL_TESTS=0
RESULTS_DIR=results
TEST_RUN_DATASET=test_run_dataset.mn

DIRNAME=$(basename $(pwd))

# number of tests per experiment / scenario
TESTS=20

# default test suite parameters
NO_AGG=n
OPT_DEV=n
OPT_TEST=n

# CHECK OPTIONS
while [ $# -gt 0 ]; do
    OPT="$1" ; shift
    if [ "$OPT_TEST" == "test" ]; then 
        echo "[OPT_TEST] - NUMBER OF TESTS - $OPT"
        TESTS="$OPT" 
        OPT_TEST=y
    fi 
    if [ "$OPT_DEV" == "max" ]; then 
        DEV_MAX="$OPT" 
        OPT_DEV=y
    fi 
    if [ "$OPT_DEV" == "min" ]; then 
        DEV_MIN="$OPT" 
        OPT_DEV=max
    fi     
    if [ "$OPT" == "-n" ]; then NO_AGG=y       ; fi
    if [ "$OPT" == "-d" ]; then OPT_DEV=min    ; fi     
    if [ "$OPT" == "-t" ]; then OPT_TEST=test  ; fi     
done

# SET factors and levels
TESTS=$(seq 1 $TESTS)
STRATEGIES="10 50"
FLAG_SYNC="0 0.1"
DEVICES="$(seq 10 10 50)"
if [ "$NO_AGG" == "y" ]; then
    # NO AGGREGATION SCENARIO
    echo '[NO_AGG] - NO AGG TEST'
    STRATEGIES="0"
    FLAG_SYNC="0"
fi
if [ "$OPT_DEV" == "y" ]; then
    echo '[OPT_DEV] - DEVICE RANGE SELECTED'
    DEVICES="$(seq ${DEV_MIN} 10 ${DEV_MAX})"
fi
echo "TESTS: $TESTS"
echo "DEVICES: $DEVICES"
echo "STRATEGIES: $STRATEGIES"
echo "FLAG_SYNC: $FLAG_SYNC"
sleep 10

show_err(){
    echo -e "./test_suite.sh [-s] 'value1 [value2]'"        
    echo -e " "
    echo -e "OPTION\tDESCRIPTION"    
    echo -e "-s\tStrategy. \t\tDEFAULT:" $STRATEGIES    
    echo -e " "
    if [ "$1" == '-h' ] || [ "$1" == '--help' ]; then
        exit 0
    else
        echo -e "ERROR: option unrecognizable '$1'"        
        exit 1
    fi
}

# the user can set custom parameters to continue from where it stopped
for opt in $@; do
    if [ "$opt" == -s ]; then
        STRATEGIES=''
        NEXT_OPTION=-s    
    elif [ "${opt:0:1}" == - ]; then
        show_err $opt    
    elif [ "$NEXT_OPTION" == -s ]; then
        STRATEGIES+="$opt "    
    else 
        show_err
    fi    
done

calculate_elapsed_time(){
    DIV=1
    if [ -n "$1" ]; then
        DIV=$1
    fi
    SEC=$(( $SECONDS / $DIV ))
    HOURS=$(( $SEC / 3600 ))
    SEC=$(( $SEC - ($HOURS * 3600) ))
    MINUTES=$(( $SEC / 60 ))
    SEC=$(( $SEC - ($MINUTES * 60) ))
    echo "${HOURS}:${MINUTES}:${SEC}"
}

chg_topo_strategy(){
    STRAT=$1
    MAX_DEVICE=$2
    TOPO=''
    for d in $(seq 1 $MAX_DEVICE); do
        TOPO="${TOPO}w"
    done    
    TOPO="${TOPO}c"
    ./chg_topo_strategy.py "$STRAT" "$TOPO"
}

run_test(){    
    DATA_PER_PKT=$1   
    SYNC=$2   
    MAX_DEVICE=$3
    # GATEWAY=$(echo $DEVICES | sed -E -e 's/[ \t]+/:/gi')
    GATEWAY=$(( ${MAX_DEVICE##*:} + 1 ))    
    # CREATE MININET TEST SCRIPT
    echo "" > "$TEST_RUN_DATASET"
    if [ $DIRNAME == 'iotp' ]; then
        for DEV_ID in $(seq 1 $MAX_DEVICE); do
            echo "h${DEV_ID} ${SEND_PY_DATASET} 10.0.1.${GATEWAY} ${DEV_ID} -a 0 -f 0 &" >> "$TEST_RUN_DATASET"
        done
        echo "h${GATEWAY} ${SEND_PY_SYNC} 10.0.1.${GATEWAY} -f ${SYNC} &" >> "$TEST_RUN_DATASET"        
    else
        for DEV_ID in $(seq 1 $MAX_DEVICE); do
            echo "h${DEV_ID} ${SEND_PY_DATASET} 10.0.1.${GATEWAY} ${DEV_ID} -a ${DATA_PER_PKT} -f ${SYNC} &" >> "$TEST_RUN_DATASET"
        done
    fi      
    echo "h${GATEWAY} sleep $(( $SAMPLE_TIME * 3 )) " >> "$TEST_RUN_DATASET"         
    echo "h${GATEWAY} sync " >> "$TEST_RUN_DATASET"
    # RUN TEST SCRIPT
    ./run.sh -r --script "$TEST_RUN_DATASET" &&
    sudo sync &&
    echo $THROUGHPUT_CALC_DATASET $DATA_PER_PKT $SAMPLE_TIME ${SYNC} "$MAX_DEVICE" ${PCAP_DIR}/*_out.pcap ${PCAP_DIR}/s1-eth${GATEWAY}_in.pcap
    $THROUGHPUT_CALC_DATASET $DATA_PER_PKT $SAMPLE_TIME ${SYNC} "$MAX_DEVICE" ${PCAP_DIR}/*_out.pcap ${PCAP_DIR}/s1-eth${GATEWAY}_in.pcap ||
    ( echo "ERROR: TEST RUN ERROR"; exit 1 )       
}


SECONDS=0
for dev in $DEVICES; do
    for strat in $STRATEGIES; do
        chg_topo_strategy $strat $dev        
        for sync in ${FLAG_SYNC}; do
            for n in $TESTS; do                 
                run_test $strat $sync $dev
                TOTAL_TESTS=$(( $TOTAL_TESTS + 1 ))
            done                          
        done                     
    done    
done

TOTAL_TEST_TIME=$(calculate_elapsed_time)
AVG_TEST_TIME=$(calculate_elapsed_time ${TOTAL_TESTS})
echo -e "\n  -----  TEST SUITE FINISHED  -----  "
echo -e "         Tests: ${TOTAL_TESTS}         "
echo -e " Avg Test Time: ${AVG_TEST_TIME}       "
echo -e "    Total Time: ${TOTAL_TEST_TIME}     "

cd ./${RESULTS_DIR}
BACKUP_FILE=results_$(date '+%F_%H-%M-%S').tar.gz
tar -cvzf ${BACKUP_FILE} *.json
rm -f *.png
cd ..
