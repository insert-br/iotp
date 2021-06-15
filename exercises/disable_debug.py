#!/usr/bin/env python

import subprocess
import json

logs_dir = './logs'
pcap_dir = './pcaps'

sw_link_map = {}

def parse_json(data):
    proc = []
    for sw in data['switches']:        
        sw_log_file = '%s/%s.log' %(logs_dir,sw)
        proc.append(subprocess.Popen(['ln','-sf','/dev/null',sw_log_file]))
        sw_link_map[sw] = 0
    for link in data['links']:
        sw = link[1]
        if link[0][0:1] == 's':
            sw = link[0]        
        sw_link_map[sw] += 1
        # sw_link_pcap = '%s/%s-eth%d_in.pcap' %(pcap_dir, sw, sw_link_map[sw])
        # proc.append(subprocess.Popen(['ln','-sf','/dev/null',sw_link_pcap]))
        # sw_link_pcap = '%s/%s-eth%d_out.pcap' %(pcap_dir, sw, sw_link_map[sw])        
        # proc.append(subprocess.Popen(['ln','-sf','/dev/null',sw_link_pcap]))
    # wait until processes finish
    while reduce(lambda x,y: x or y, map(lambda x: x.poll() is None, proc)):
        pass

with open('topology.json') as json_file:  
    data = json.load(json_file)
    parse_json(data)
