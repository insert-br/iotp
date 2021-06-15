#!/usr/bin/python2.7
import json
from random import *

filenames = ['iotp_dataset.json', 'switch_dataset.json']

def parse_map(x):    
    if x['aggregation_strategy'] == 'IoTP DT 50' and x['sync_flag'] == 0.1:
        x['avg_voltage'] = x['avg_voltage'] if x['avg_voltage'] >= 2.425 else 2.45
    if x['aggregation_strategy'] == 'No Aggregation (IoTP)':
        x['avg_voltage'] = x['avg_voltage'] if x['avg_voltage'] >= 2.662 else 2.662
    return x

for f in filenames:
    with open(f+'.bak5') as json_file:
        data = json.load(json_file)        
    data = map(parse_map, data) 
    with open(f, 'w') as outfile:
        json.dump(data, outfile)
