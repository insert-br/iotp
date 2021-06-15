#!/bin/bash
TIMESTAMP=$(date '+%F_%H-%M-%S')
IFACE=$(ifconfig | grep eth | cut -d ' ' -f1)
IP_SRC=$(ifconfig ${IFACE} | grep 'inet addr' | cut -d ':' -f2 | cut -d ' ' -f1)
HOST=$(echo $IFACE | cut -d '-' -f1)

PCAP_DIR=./pcaps
LOG_DIR=./logs

SEND_PY=./send.py 
SEND_PY_DATASET=./send_dataset.py 
SEND_PY_SYNC=./send_sync.py 
THROUGHPUT_CALC=./throughput.py
THROUGHPUT_CALC_DATASET=./throughput_dataset.py

SAMPLE_TIME=10
CAP_REPLAY_FILE=./replay.pcap

get_ip(){
    SERVER_IP=$1
    if [ ${SERVER_IP:0:1} == 'h' ]; then
        SERVER_IP=${SERVER_IP:1:2}
        SERVER_IP="10.0.${SERVER_IP}.${SERVER_IP}"
    elif [ ${SERVER_IP:0:1} == 's' ]; then        
        SERVER_IP="10.0.${SERVER_IP:1:1}.${SERVER_IP:3:4}"
    fi
    echo "$SERVER_IP"
} 

is_running(){
    isPID=$(ps -ef | grep ${1} | grep -v grep | sed -E -e 's/ +/ /gi'  | cut -d ' ' -f 2)
    if [ -z "$isPID" ]; then
        return 1 
    fi   
    return 0
}