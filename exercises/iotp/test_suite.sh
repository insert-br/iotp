#!/bin/bash

TOTAL_TESTS=0
RESULTS_DIR=results

DIRNAME=$(basename $(pwd))

# default test suite parameters
# TESTS=$(seq 16 20)
TESTS=$(seq 1 20)
#TOPOLOGIES='wc cc ww cw'
TOPOLOGIES='wc'
STRATEGIES=$(seq 10 10 50)
DPPS="1 $(seq 10 10 20)"
PPSS=$(seq 1000 1000 5000)

if [ $DIRNAME != 'iotp' ]; then    
    STARTEGIES=10   
fi

show_err(){
    echo -e "./test_suite.sh [-t|-s|-d|-p] 'value1 [value2]'"        
    echo -e " "
    echo -e "OPTION\tDESCRIPTION"
    echo -e "-t\tTopology. \t\tDEFAULT:" $TOPOLOGIES
    echo -e "-s\tStrategy. \t\tDEFAULT:" $STRATEGIES
    echo -e "-d\tData per Packet. \tDEFAULT:" $DPPS
    echo -e "-p\tPackets Per Second. \tDEFAULT:" $PPSS
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
    if [ "$opt" == -t ]; then
        TOPOLOGIES=''
        NEXT_OPTION=-t
    elif [ "$opt" == -s ]; then
        STRATEGIES=''
        NEXT_OPTION=-s
    elif [ "$opt" == -d ]; then
        DPPS=''
        NEXT_OPTION=-d
    elif [ "$opt" == -p ]; then
        PPSS=''
        NEXT_OPTION=-p
    elif [ "${opt:0:1}" == - ]; then
        show_err $opt
    elif [ "$NEXT_OPTION" == -t ]; then
        TOPOLOGIES+="$opt "
    elif [ "$NEXT_OPTION" == -s ]; then
        STRATEGIES+="$opt "
    elif [ "$NEXT_OPTION" == -d ]; then
        DPPS+="$opt "
    elif [ "$NEXT_OPTION" == -p ]; then
        PPSS+="$opt "
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
    TOPO=$2
    ./chg_topo_strategy.py "$STRAT" "$TOPO"
}

run_test(){
    PPS=$1
    DATA_PER_PKT=$2    
    ./run.sh -r -s "h1 ./test_run.sh $PPS $DATA_PER_PKT"    
}

SECONDS=0
for topo in $TOPOLOGIES; do
    for strat in $STRATEGIES; do
        chg_topo_strategy $strat $topo
        for dpp in $DPPS; do
            for pps in $PPSS; do
                for n in $TESTS; do                        
                    # echo $n $pps $dpp $strat $topo                    
                    run_test $pps $dpp
                    TOTAL_TESTS=$(( $TOTAL_TESTS + 1 ))                        
                done
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
cd ..
