#!/usr/bin/env python

from threading import Thread, Event, Lock
# from Queue import Queue
# import functools
# import os
import subprocess
import time
import signal
import argparse
import sys
import os
import socket
import random
import struct

import numpy as np
import pandas as pd
from scapy.all import *

from iotp import *

class RepeatedTimer(Thread):
    def __init__(self, finishEvent, wtime, func, *fargs):
        Thread.__init__(self)
        self.wtime = wtime
        self.func = func
        self.fargs = fargs
        self.stopped = finishEvent

    def run(self):
        while not self.stopped.wait(self.wtime):
            self.func(*self.fargs)

def timer_send_stored_pkts(sendObj):
    # print 'timer awaken'
    sendObj.send_lock.acquire()
    # print '[thread]', len(sendObj.pkts_to_send)
    for idx, record in sendObj.pkts_to_send.items():
        # print 'timer send', idx
        # set delay equal to timer int and send pkt
        record['pkt'].options[0].value = str(sendObj.sync_timer['interval'] * 1e6)
        sendObj.socket.send(record['pkt']) 
        # set throughput and goodput
        sendObj.pkts_len += len(record['pkt']) 
        sendObj.pkts_goodput += record['data_len'] * 8
        # delete pkt
        del sendObj.pkts_to_send[idx]
        sendObj.pkts_num += 1
    sendObj.send_lock.release()
    # print 'timer release'

class Send:
    def __init__(self):
        signal.signal(signal.SIGINT, self.exit_gracefully)
        signal.signal(signal.SIGTERM, self.exit_gracefully)  
        self.dirname = os.getcwd().split('/')[-1]
        self.dataset_filename = 'datasets/intel_data_filtered.csv'
        self.data_headers = Data.headers
        self.total_simulation_time = 10
        self.real_time_to_simulation_time = 360.0
        self.pkts_num = 0
        self.pkts_len = 0      
        self.pkts_goodput = 0  
        self.pkts_to_send = {}        
        self.pkts_delays = {}        
        self.get_if()
        self.parse_args()   
        self.load_dataset()     

    def exit_gracefully(self, signum, frame):
        # stop thread
        if self.sync_timer:
            self.sync_timer['stop'].set()
        print " "
        print "        Device ID: %d "       %( self.device_id      )        
        if self.aggregate_data <= 1:
            print "      Aggregation: Disabled "
        else:
            print "      Aggregation: %d blocks " %( self.aggregate_data )
        print " ----------------------------------  "
        print "   Packets: %d"       %( self.pkts_num     )        
        print "   Goodput: %d B"     %( self.pkts_goodput )                     
        print "Throughput: %d B"     %( self.pkts_len     )                     
        print "       G/T: %5.2f %%" %( float(self.pkts_goodput) / self.pkts_len * 100.0 )
        for i in self.pkts_delays:            
            if self.pkts_delays[i][-1] == 0:
                self.pkts_delays[i].pop()   
            # no delay can surpass the timer delay, adjust for it
            if self.sync_timer:
                sync_timer_int_us = self.sync_timer['interval']*1e6
                self.pkts_delays[i] = map(lambda x: min(x,sync_timer_int_us), self.pkts_delays[i])
        print " Avg Delay: %f ms" %( reduce(lambda x,y: (x+y)/2, map(np.mean, self.pkts_delays.values())) / 1e3 )
        sys.exit(0)           

    def get_if(self):
        ifs = get_if_list()
        iface = None
        for i in get_if_list():
            if "eth0" in i:
                iface=i
                break
        if not iface:
            print "Cannot find eth0 interface"
            exit(1)
        self.iface = iface 
        self.hw_addr_src = get_if_hwaddr(self.iface)
        self.socket = conf.L2socket(iface=self.iface)                
        print "sending on interface %s" % (self.iface)

    def parse_args(self):
        if len(sys.argv) < 3 or sys.argv[0] == '-h' or sys.argv[0] == '--help':
            print 'pass 2 arguments: <host_destination> <device_id>'
            exit(1)        
        self.parse_dst_ip_hw(sys.argv[1])   
        self.device_id = int(sys.argv[2])
        self.parse_options(sys.argv[3:])     

    def parse_options(self, options):     
        self.get_pkt = self.get_pkt_iotp if self.dirname == 'iotp' else self.get_pkt_normal             
        self.aggregate_data = 1
        self.sync_timer = {}
        self.send_lock = Lock()
        idx = 0
        for opt in options:
            if opt == '-a':                
                self.aggregate_data = int(options[idx+1])
            elif opt == '-f':
                if float(options[idx+1]) > 0:
                    self.sync_timer['stop'] = Event()
                    self.sync_timer['interval'] = float(options[idx+1])
                    self.sync_timer['timer'] = RepeatedTimer(self.sync_timer['stop'], self.sync_timer['interval'], timer_send_stored_pkts, self) 
                else:
                    print '[IoT] pass timer sync interval'
            idx += 1

    def load_dataset(self):
        self.dataset = pd.read_csv(self.dataset_filename, sep=',', decimal='.', index_col=False)
        self.dataset = self.dataset[ self.dataset['id'] == self.device_id ]

    def parse_dst_ip_hw(self, ip_str):        
        self.ip_addr_dst = socket.gethostbyname(ip_str)                            
        ip_splitted = str(self.ip_addr_dst).split('.')
        self.hw_addr_dst = '00:00:00:00:%02x:%02x' % (int(ip_splitted[2]), int(ip_splitted[3]))    

    def handle_pkt(self):
        print 'SEND - STARTED'      
        running_time = 0.0  
        record_id = 0       
        if self.sync_timer:
            self.sync_timer['timer'].start()
        while running_time < self.total_simulation_time:
            self.record = self.dataset.iloc[record_id, :] 
            # adjust time window from sec to us and from dataset time to simulation time   
            self.record['timedelta'] = (self.record['timedelta'] / self.real_time_to_simulation_time) * 1e6      
            self.send_lock.acquire()
            # print '[main thread] get pkt'
            for pkt in self.get_pkt():
                # print '[main thread] send pkt'
                self.socket.send(pkt) 
                self.pkts_num += 1
                self.pkts_len += len(pkt)      
            self.send_lock.release()
            # define simulation time to be faster than real world dataset time            
            wait_time = self.record['timedelta'] / 1e6
            time.sleep(wait_time) 
            running_time += wait_time
            record_id += 1
        print 'SEND - TERMINATED'        

    def get_pkt_normal(self):        
        pkts = []
        idx = 0        
        for data in self.record[self.data_headers]:  
            # print data
            if idx not in self.pkts_delays:
                self.pkts_delays[idx] = [0]                      
            if idx not in self.pkts_to_send:
                # create a new packet to send through the wire
                pkt = Ether(src=self.hw_addr_src, dst=self.hw_addr_dst) / IP(dst=self.ip_addr_dst, options=IPOption(value=0))
                pkt = pkt / UDP(dport=Data.udp_base_port + idx, sport=random.randint(1025,65535))
                self.pkts_to_send[idx] = {
                    'pkt': pkt,                
                    'data_len': 0
                }            
            # store data into the packet
            pkt_record = self.pkts_to_send[idx]
            pkt_record['pkt'] = pkt_record['pkt'] / IOTPData(data=data)            
            # pkt_record['pkt'] = pkt_record['pkt'] / ("%08d" %(data))
            pkt_record['data_len'] += 1            
            # once we acquired enough data, send the packet out to the NIC
            if pkt_record['data_len'] >= self.aggregate_data:                
                self.pkts_goodput += pkt_record['data_len'] * 8
                # reset next packet delay
                self.pkts_delays[idx].append(0)
                # return IPOptions value to str
                pkt_record['pkt'].options[0].value = str(pkt_record['pkt'].options[0].value)
                # send packet out
                pkts.append(pkt_record['pkt'])
                del self.pkts_to_send[idx]
            else:                
                # we did not sent the data out, so we store the accumulated 
                # delay related to the aggregation                
                pkt_record['pkt'].options[0].value += self.record['timedelta']
                self.pkts_delays[idx][-1] += self.record['timedelta']                   
                # print '--- delay here ---'
            idx += 1
        # for p in pkts:
        #     p.show()
            # print '--- next ---'
        # print ' '
        return pkts

    def get_pkt_iotp(self):        
        pkts = []        
        idx = 0
        for data in self.record[self.data_headers]:                       
            if idx not in self.pkts_delays:
                self.pkts_delays[idx] = [0]           
            if idx not in self.pkts_to_send:
                # create a new packet to send through the wire
                pkt = IOTP(id=idx, count=0, delay=0, flags=0, type=IOTP.itype)
                pkt = pkt / Ether(src=self.hw_addr_src, dst=self.hw_addr_dst, type=IOTP.etype) 
                self.pkts_to_send[idx] = {
                    'pkt': pkt,                
                    'data_len': 0
                } 
            # store data into the packet
            pkt_record = self.pkts_to_send[idx]
            pkt_record['pkt'] = pkt_record['pkt'] / IOTPData(data=data)
            pkt_record['data_len'] += 1
            # once we acquired enough data, send the packet out to the NIC
            if pkt_record['data_len'] >= self.aggregate_data:
                self.pkts_goodput += (pkt_record['data_len'] * 8)
                pkt_record['pkt'].count = pkt_record['data_len']                
                # reset next packet delay
                self.pkts_delays[idx].append(0)
                # send packet out
                pkts.append(pkt_record['pkt'])
                del self.pkts_to_send[idx]    
            else:
                # we did not sent the data out, so we store the accumulated 
                # delay related to the aggregation
                # pkt_record['pkt'].delay += self.record['timedelta']
                self.pkts_delays[idx][-1] += self.record['timedelta']                
            idx += 1                        
        return pkts

    def get_header_info(self, pkt):
        if isinstance(pkt,Ether):
            s = 'Ether type %d / ' %(pkt.type)
        elif isinstance(pkt,IP):
            s = "IP src %s dst %s / " %(pkt.src, pkt.dst)         
        elif isinstance(pkt,TCP):
            s = "TCP sp %d dp %d / " %(pkt.sport, pkt.dport)
        elif isinstance(pkt,UDP):
            s = "UDP sp %d dp %d / " %(pkt.sport, pkt.dport)
        elif isinstance(pkt,IOTP):        
            s = "IOTP id %d / " %(pkt.id) 
        elif isinstance(pkt,IOTPData):        
            s = "IOTPData data %d" %(pkt.data)
        else:
            s = "Raw %s / " %(pkt.load)
        return s

    def show_report(self, pkt):
        print ' ' 
        print '-----  REPORT  -----' 
        s = ''
        while not isinstance(pkt, NoPayload):
            s += self.get_header_info(pkt)                    
            pkt = pkt.payload
        print ' '
        print s  
        print ' '        

    def run(self):
        print ' '
        print 'GENERATING PACKETS ...'                
        self.handle_pkt()        
        self.exit_gracefully(0, 0)

if __name__ == '__main__':    
    send = Send()    
    send.run()    

    
    
    

