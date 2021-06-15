#!/usr/bin/env python

# from threading import Thread
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

class Send:
    def __init__(self):
        signal.signal(signal.SIGINT, self.exit_gracefully)
        signal.signal(signal.SIGTERM, self.exit_gracefully)  
        self.dirname = os.getcwd().split('/')[-1]        
        self.data_headers = ['temp','humidity','light','volt']
        self.total_simulation_time = 10            
        self.pkts_num = 0
        self.pkts_len = 0      
        self.pkts_goodput = 0  
        self.get_if()
        self.parse_args()      

    def exit_gracefully(self, signum, frame):   
        print " ----------------------------------  "
        print "   Packets: %d"       %( self.pkts_num     )        
        print "   Goodput: %d B"     %( self.pkts_goodput )                     
        print "Throughput: %d B"     %( self.pkts_len     )                     
        print "       G/T: %5.2f %%" %( float(self.pkts_goodput) / self.pkts_len * 100.0 )     
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
        if len(sys.argv) < 2 or sys.argv[0] == '-h' or sys.argv[0] == '--help':
            print 'pass 2 arguments: <host_destination>'
            exit(1)        
        self.parse_dst_ip_hw(sys.argv[1])  
        self.parse_options(sys.argv[2:])     

    def parse_options(self, options):     
        self.get_pkt = self.get_pkt_iotp if self.dirname == 'iotp' else self.get_pkt_normal                     
        idx = 0
        self.flag_sync_time = 0
        for opt in options:
            if opt == '-f':                
                self.flag_sync_time = float(options[idx+1])
            idx += 1
        if self.flag_sync_time == 0:
            print 'pass flag sync argument with -f'
            sys.exit(1)

    def parse_dst_ip_hw(self, ip_str):        
        self.ip_addr_dst = socket.gethostbyname(ip_str)                            
        ip_splitted = str(self.ip_addr_dst).split('.')
        self.hw_addr_dst = '00:00:00:00:%02x:%02x' % (int(ip_splitted[2]), int(ip_splitted[3]))    

    def handle_pkt(self):
        print 'SEND - STARTED'      
        running_time = 0.0                
        wait_time = self.flag_sync_time
        while running_time < self.total_simulation_time:               
            for pkt in self.get_pkt():
                self.socket.send(pkt) 
                self.pkts_num += 1
                self.pkts_len += len(pkt)                
            # define simulation time to be faster than real world dataset time            
            # print 'ok'
            time.sleep(wait_time) 
            running_time += wait_time
        print 'SEND - TERMINATED'        

    def get_pkt_normal(self):      
        return []

    def get_pkt_iotp(self):        
        pkts = []        
        idx = 0
        for data in self.data_headers:  
            pkt = IOTP(id=idx, count=0, delay=0, flags=1, type=IOTP.itype)
            pkt = pkt / Ether(src=self.hw_addr_src, dst=self.hw_addr_dst, type=IOTP.etype) 
            pkts.append(pkt)         
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

    
    
    

