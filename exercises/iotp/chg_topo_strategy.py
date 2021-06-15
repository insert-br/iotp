#! /usr/bin/env python
import sys
import json
import os
import time

runtime_file = 's1-runtime.json'
topology_file = 'topology.json'
topology_type_file = 'topology_type.json'

strategy = int(sys.argv[1])
topology = sys.argv[2]

dirname = os.getcwd().split('/')[-1]

def chg_topology():    
    print "Reading topology map ..."
    with open(topology_type_file) as json_file:  
        data_type = json.load(json_file)
        data_type['topology'] = topology
        conf = [data_type['links'][topo] for topo in topology]             
    with open(topology_file) as json_file:  
        data = json.load(json_file)
        data['links'] = []        
        data['hosts'] = []        
        for i in xrange(1,len(conf)+1):
            data['hosts'].append("h%d" % i)        
            data['links'].append(["h%d" % i, "s1", conf[i-1][0], conf[i-1][1]])            
    print "Reading P4 Runtime strategy ..."
    with open(runtime_file) as json_file:  
        data_runtime = json.load(json_file)
        data_runtime['table_entries'] = filter(lambda e: e['table'] != 'MyIngress.eth_tbl_forward', data_runtime['table_entries'])
        for i in xrange(1,len(conf)+1):
            data_runtime['table_entries'].append({
                "action_name": "MyIngress.eth_forward", 
                "action_params": {
                    "port": i
                }, 
                "match": {
                    "hdr.ethernet.dstAddr": "00:00:00:00:01:%02x" % i
                }, 
                "table": "MyIngress.eth_tbl_forward"
            })
    print "Changing Mininet topology ..."
    with open(topology_file, 'w') as json_file:  
        json.dump(data, json_file, indent=4)
    with open(topology_type_file, 'w') as json_file:  
        json.dump(data_type, json_file, indent=4)
    with open(runtime_file, 'w') as json_file:  
        json.dump(data_runtime, json_file, indent=4)
    print "DONE"

def chg_strategy():
    print "Reading P4 Runtime strategy ..."
    with open(runtime_file) as json_file:  
        data = json.load(json_file)
        iotp_count_l = filter(lambda e: 'meta.iotp_count' in e['match'], data['table_entries'])[0]['match']['meta.iotp_count']
        iotp_count_l[0] = strategy       
    print "Changing strategy ..."
    with open(runtime_file, 'w') as json_file:  
        json.dump(data, json_file, indent=2, sort_keys=True) 
    print "DONE"    

chg_topology()
if dirname == 'iotp':
    chg_strategy()
