#!/bin/bash
. ../utils.sh

PPS=$1
DATA_PER_PKT=$2

if [ $# -lt 1 ]; then
    echo 'ERROR: ./test_run.sh <PPS> [<DATA_PER_PKT>]'
    exit 1
fi

if [ -z "$DATA_PER_PKT" ]; then
    DATA_PER_PKT=1
fi

check_simple_sw_cpu_usage(){
    top -b -n 1 | grep simple_sw | sed -E -e 's/[ \t]+/ /gi' | xargs | cut -d ' ' -f 9 
}

check_cpu_usage(){
    top -b -n 1 | head -n 8 | tail -n 1 | sed -E -e 's/[ \t]+/ /gi' | xargs | cut -d ' ' -f 9 
}

while [ $(python -c "print $(check_cpu_usage) < 10.0") == "False" ]; do    
    echo -e '\nWAITING FOR CPU TO STABILIZE...\n'
    sleep 1
done
"$SEND_PY" 10.0.1.2 0 "[1,${DATA_PER_PKT}]" -t "$PPS" "$SAMPLE_TIME"
while [ "$(check_simple_sw_cpu_usage)" != "0.0" ]; do    
    echo -e '\nWAITING FOR SIMPLE SWITCH TO FINISH PROCESSING...\n'
    sleep 1
done
echo -e '  #### CALCULATING NETWORK METRICS  ####  \n'
"$THROUGHPUT_CALC" "$DATA_PER_PKT" "$PPS" "$SAMPLE_TIME" "${PCAP_DIR}/s1-eth1_out.pcap" "${PCAP_DIR}/s1-eth2_in.pcap"