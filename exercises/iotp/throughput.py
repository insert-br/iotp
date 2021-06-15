#! /usr/bin/env python
import sys
import json
import os
import time

from scapy.all import *
from scapy.packet import NoPayload
from collections import Counter

from send import Send
from iotp import *

data_per_pkt = int(sys.argv[1])
replay_pps = int(sys.argv[2])
sample_interval = float(sys.argv[3])
in_capture_file = sys.argv[4]
out_capture_file = sys.argv[5]

dirname = os.getcwd().split('/')[-1]
dirname = dirname.replace('iotp_','')
json_results = 'results/' + dirname + '.json'

test_num = 1
json_results_data = []
json_data = {
    'goodput': 0,
    'throughput': 0,
    'avg_delay': 0,    
    'pkt_send': 0,
    'pkt_recv': 0,    
    'pps_tcpreplay': replay_pps,    
    'sample_int': sample_interval,
    'data_per_pkt': data_per_pkt
}

with open('topology_type.json') as json_file:  
    data = json.load(json_file)
    json_data['topology'] = data['topology']

try:
    with open(json_results) as json_file:
        json_results_data = json.load(json_file)
except IOError:
    pass

with open('s1-runtime.json') as json_file:  
    data = json.load(json_file)
    iotp_count = filter(lambda e: 'meta.iotp_count' in e['match'], data['table_entries'])
    if len(iotp_count) > 0:
        iotp_count = str(iotp_count[0]['match']['meta.iotp_count'][0])
        json_data['aggregation_strategy'] = 'IOTP DT ' + iotp_count
    else:
        iotp_count = str(1)   
        json_data['aggregation_strategy'] = 'L2 Switch' 
    test_num += len(filter(
        lambda x: int(x['data_per_pkt']) == json_data['data_per_pkt'] and int(x['pps_tcpreplay']) == json_data['pps_tcpreplay'] and x['aggregation_strategy'] == json_data['aggregation_strategy'] and x['topology'] == json_data['topology'], 
        json_results_data))
    json_results_data.append(json_data)
    
def human(num):
    for x in ['k', 'M', 'G', 'T']:
        if num < 1024.: return "% 6.1f %sB" % (num, x)
        num /= 1024.
    return  "% 6.1f PB" % (num)

def parse_pkt(s):    
    if dirname == 'switch':
        return Ether(s)
    else:
        return IOTP(s)

def get_packet_data(pkt):
    if IOTPData in pkt:
        pkt = pkt[IOTPData]
    elif UDP in pkt:
        pkt = pkt[UDP].payload
    elif TCP in pkt:
        pkt = pkt[TCP].payload
    else:
        pkt = NoPayload()
    return pkt   
    

print ' '
print 'TEST #%d'  %(test_num) 
print '%s' %(json_data['aggregation_strategy'])
print '         TOPOLOGY: %s' %(json_data['topology'])
print "TEST INTERVAL (s): %.2f" %(json_data['sample_int'])
print '  DATA PER PACKET: %d' %(json_data['data_per_pkt'])
print ' TCP REPLAY (PPS): %d' %(json_data['pps_tcpreplay'])
print ' '
print '  ####  PROCESSING ...  ### '

# read pkts sent (really fast operation here)
for s, _ in RawPcapReader(in_capture_file):        
    json_data['pkt_send'] += 1   

# A trick I like: don't use rdpcap() that would waste your memory;
# iterate over a PcapReader object instead.
for s, _ in RawPcapReader(out_capture_file):
    # half the time of the loop is the Scapy dissecting below    
    p = parse_pkt(s)
    pkt_payload = get_packet_data(p)
    if not isinstance(pkt_payload, NoPayload):        
        json_data['goodput']    += len(pkt_payload)
        # speed up, len(s) is faster than len(p)
        json_data['throughput'] += len(s) 
        json_data['pkt_recv']   += 1
        if isinstance(p, IOTP):
            json_data['avg_delay'] += p.delay    

json_data['gt'] = float(json_data['goodput']) / float(json_data['throughput']) * 100. if json_data['throughput'] != 0 else 0.
json_data['pkt_loss'] = (float(json_data['pkt_send'])/float(iotp_count) - json_data['pkt_recv'])/json_data['pkt_send'] * 100. if json_data['pkt_send'] != 0 else 0.
json_data['avg_delay'] = float(json_data['avg_delay'])/(json_data['pkt_recv']*1000.)
json_data['throughput'] = float(json_data['throughput'])/(json_data['sample_int']*1024.)
json_data['goodput'] = float(json_data['goodput'])/(json_data['sample_int']*1024.)
json_data['pps_recv'] = float(json_data['pkt_recv'])/json_data['sample_int']
json_data['pps_send'] = float(json_data['pkt_send'])/json_data['sample_int']

print ' '
print "Packets (SEND / RECV): %d / %d" %(json_data['pkt_send'],json_data['pkt_recv'])
print "PPS (SEND / RECV):     %.2f / %.2f" %(json_data['pps_send'], json_data['pps_recv'])
print " Avg Delay: %.2f ms" % ( json_data['avg_delay'] )
print "Throughput: %s/s" % (human( json_data['throughput'] ))
print "   Goodput: %s/s" % (human( json_data['goodput'] ))
print "G/T: %6.2f %%" % ( json_data['gt'] )
print "Packet Loss: %6.2f %%" %(json_data['pkt_loss'])

with open(json_results, 'w') as outfile:  
    json.dump(json_results_data, outfile)
