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

if len(sys.argv) < 6:
    print 'ERROR - THROUGHPUT.PY: invalid arguments <dpp> <sample> <sync> <in pcap> <out pcap>'
    sys.exit(1)

data_per_pkt = int(sys.argv[1])
sample_interval = float(sys.argv[2])
sync_flag = float(sys.argv[3])
devices = int(sys.argv[4])

in_capture_file = sys.argv[5:-1]
out_capture_file = sys.argv[-1]

dirname = os.getcwd().split('/')[-1]
dirname = dirname.replace('iotp_','')
json_results = 'results/' + dirname + '_dataset.json'

test_num = 1
json_results_data = []
json_data = {
    'goodput': 0,
    'throughput': 0,
    'avg_delay': 0.0,    
    'pkt_send': 0,
    'pkt_recv': 0, 
    'avg_voltage': 0.0,     
    'pkt_recv_voltage': 0,
    'sample_int': sample_interval,
    'data_per_pkt': data_per_pkt, 
    'sync_flag': sync_flag,    
    'devices': devices
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
        iotp_count = iotp_count[0]['match']['meta.iotp_count'][0]
        json_data['aggregation_strategy'] = 'IoTP DT %d' % iotp_count        
        if iotp_count <= 1:
            iotp_count = 1
            json_data['aggregation_strategy'] = 'No Aggregation (IoTP)'
    else:        
        iotp_count = 1
        json_data['aggregation_strategy'] = 'No Aggregation (L2 Switch)'
        if data_per_pkt > 1:
            iotp_count = data_per_pkt 
            json_data['aggregation_strategy'] = 'L2 Switch DT %d' % iotp_count            
    test_num += len(filter(
        lambda x: int(x['data_per_pkt']) == json_data['data_per_pkt'] and x['aggregation_strategy'] == json_data['aggregation_strategy'] and x['devices'] == json_data['devices'], 
        json_results_data))
    json_results_data.append(json_data)
    
def human(num):
    for x in ['', 'k', 'M', 'G', 'T']:
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
    
def process_iotp(p, pkt_payload):    
    json_data['avg_delay'] += p.delay       
    if p.id == Data.header_map['volt']:
        voltage = 0.0
        while isinstance(pkt_payload, IOTPData):            
            data = round(pkt_payload.data / 1e1, 1)
            # print 'ID:', p.id, ' Volt:', data
            voltage = data if data > 0.0 and (voltage == 0.0 or data < voltage) else voltage
            pkt_payload = pkt_payload.payload
        json_data['avg_voltage'] += voltage
        json_data['pkt_recv_voltage'] += 1
        # print '-----> Voltage:', voltage, ' AVG:', json_data['avg_voltage']

def process_udp(p, pkt_payload):
    json_data['avg_delay'] += float(re.sub(r'[^\d\.]+', '', reduce(lambda a,b: str(a) + str(b), p.options)))
    if UDP in p and p['UDP'].dport == (Data.udp_base_port + Data.header_map['volt']):
        pkt_payload = IOTPData(str(pkt_payload))
        voltage = 0.0
        while isinstance(pkt_payload, IOTPData):
            data = round(pkt_payload.data / 1e1, 1)          
            # print 'ID:', p['UDP'].dport, ' Volt:', data
            voltage = data if data > voltage else voltage
            pkt_payload = pkt_payload.payload
        json_data['avg_voltage'] += voltage
        json_data['pkt_recv_voltage'] += 1
        # print '-----> Voltage:', voltage, ' AVG:', json_data['avg_voltage']

# print "TEST INTERVAL (s): %.2f" %(json_data['sample_int'])
print ' '
print 'TEST #%d'  %(test_num) 
print '%s' %(json_data['aggregation_strategy'])
print '          DEVICES: %s' %(json_data['devices'])
print '             SYNC: %s' %(json_data['sync_flag'])
print '  DATA PER PACKET: %d' %(json_data['data_per_pkt'])
print ' '
print '  ####  PROCESSING ...  ### '

# read pkts sent (really fast operation here)
for in_file in in_capture_file:
    try:
        for s, _ in RawPcapReader(in_file):        
            json_data['pkt_send'] += 1   
    except:
        pass

# A trick I like: don't use rdpcap() that would waste your memory;
# iterate over a PcapReader object instead.
for s, _ in RawPcapReader(out_capture_file):
    # half the time of the loop is the Scapy dissecting below    
    p = parse_pkt(s)
    pkt_payload = get_packet_data(p)
    # if not isinstance(pkt_payload, NoPayload):        
    json_data['goodput'] += len(pkt_payload)
    # speed up, len(s) is faster than len(p)
    json_data['throughput'] += len(s) 
    json_data['pkt_recv']   += 1    
    if isinstance(p, IOTP):
        process_iotp(p, pkt_payload)        
    else:            
        process_udp(p, pkt_payload)

json_data['gt'] = float(json_data['goodput']) / float(json_data['throughput']) * 100. if json_data['throughput'] != 0 else 0.
json_data['pkt_loss'] = (float(json_data['pkt_send'])/float(iotp_count) - json_data['pkt_recv'])/json_data['pkt_send'] * 100. if json_data['pkt_send'] != 0 else 0.
json_data['avg_delay'] = float(json_data['avg_delay'])/(json_data['pkt_recv']*1e3)
json_data['throughput'] = float(json_data['throughput'])/(json_data['sample_int'])
json_data['goodput'] = float(json_data['goodput'])/(json_data['sample_int'])
json_data['pps_recv'] = float(json_data['pkt_recv'])/json_data['sample_int']
json_data['pps_send'] = float(json_data['pkt_send'])/json_data['sample_int']
json_data['avg_voltage'] = float(json_data['avg_voltage']/json_data['pkt_recv_voltage'])
del json_data['pkt_recv_voltage']

print ' '
print "Packets (SEND / RECV): %d / %d" %(json_data['pkt_send'],json_data['pkt_recv'])
print "PPS (SEND / RECV):     %.2f / %.2f" %(json_data['pps_send'], json_data['pps_recv'])
print " Avg Delay: %.2f ms" % ( json_data['avg_delay'] )
print "Throughput: %s/s" % (human( json_data['throughput'] ))
print "   Goodput: %s/s" % (human( json_data['goodput'] ))
print "G/T: %6.2f %%" % ( json_data['gt'] )
print "Packet Loss: %6.2f %%" %(json_data['pkt_loss'])
print "Avg Voltage: %.4f mV" %(json_data['avg_voltage'])

with open(json_results, 'w') as outfile:  
    json.dump(json_results_data, outfile)
