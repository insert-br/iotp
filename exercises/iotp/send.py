#!/usr/bin/env python
from threading import Thread, Event, Lock
import subprocess
import time
from datetime import datetime

import sys, os, signal, socket, argparse, getopt
import random
import struct

import numpy as np
import pandas as pd

from scapy.all import *
from ndn_adap import *

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

class Simulation:
    def __init__(self):
        signal.signal(signal.SIGINT,  self.exit_gracefully)
        signal.signal(signal.SIGTERM, self.exit_gracefully)  
        self.dirname = os.getcwd().split('/')[-1].replace('ndn_adap_', '')        
        self.total_simulation_time = 12.0        
        self.udp_base_port = 1025        
        # maximum amount of pkts in RAM per thread
        self.mem_max_pkts = 50
        # defines the pkt send load
        self.pkts_slow_send = {
            # 'begin': 500,
            # 'end': 1000,
            'begin': 0,
            'end': 10000,
            'pps': 150.0
        }
        self.pkts_num = 0
        self.pkts_len = 0      
        self.pkts_goodput = 0  
        self.pkts_to_send = {}        
        self.pkts_delays = {}        
        self.get_if()
        self.parse_args()      

    def exit_gracefully(self, signum, frame):
         # stop thread
        # if self.sync_timer:
        #     self.sync_timer['stop'].set()        
        print " ----------------------------------  "
        print 'Simulation run:', (datetime.now() - self.simulation_start).total_seconds(), 's'
        print " ----------------------------------  "
        print "   Packets: %d  "     %( self.pkts_num     )        
        print "   Goodput: %d B"     %( self.pkts_goodput )                     
        print "Throughput: %d B"     %( self.pkts_len     )                     
        print "       G/T: %5.2f %%" %( float(self.pkts_goodput) / self.pkts_len * 100.0 )
        # for i in self.pkts_delays:            
        #     if self.pkts_delays[i][-1] == 0:
        #         self.pkts_delays[i].pop()               
        # print " Avg Delay: %f ms" %( reduce(lambda x,y: (x+y)/2, map(np.mean, self.pkts_delays.values())) / 1e3 )
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

    def parse_dst_ip_hw(self, ip_str):        
        self.ip_addr_dst = socket.gethostbyname(ip_str)                            
        ip_splitted = str(self.ip_addr_dst).split('.')
        self.hw_addr_dst = '00:00:00:00:%02x:%02x' % (int(ip_splitted[2]), int(ip_splitted[3]))    
    
    def parse_options(self, argv):
        # self.sync_timer = {}
        # self.send_lock = Lock()
        self.test_mode = True
        self.get_pkt = self.get_pkt_ndn_adap if self.dirname == 'ndn_adap' else self.get_pkt_normal                    
        # print argv
        usage = 'usage: send.py <name> <ndn_pkt_type> <route> <-T, --slow-pps, --fast-begin, --fast-end>'
        try:
            # parse cmdline options
            opts, args = getopt.getopt(argv,"hT",['slow-pps=','fast-begin=','fast-end='])
        except getopt.GetoptError as e:
            print e
            print usage
            sys.exit(2)
        for opt, arg in opts:
            if opt == '-h':
                print usage
                sys.exit()
            elif opt == '-T':
                self.test_mode = False
            elif opt in ("--slow-pps"):
                self.pkts_slow_send['pps'] = float(arg)
            elif opt in ('--fast-begin'):
                self.pkts_slow_send['begin'] = int(arg)
            elif opt in ('--fast-end'):
                self.pkts_slow_send['end'] = int(arg)

    def parse_args(self):
        if len(sys.argv) < 4:            
            if self.dirname == 'ndn_adap':
                print 'pass 4 arguments: <content name> <interest|data> "[(<mcast|port>,<mcast_port>)]" [<options>]'
            else:
                print 'pass 4 arguments: <content name> <interest|data> <dest_IP> [<options>]'
            exit(1)        
        self.ndn_options = {
            'name': '',
            'type': 'interest',
            'canBePrefix': True,
            'mustBeFresh': True,
            'nonce':  0x32,
            'interestLifetime': 4000,
            'hopLimit': 1,
            'content': '',
            'signatureInfoType': 0,
            'signatureValue': 4000,        
        }
        self.ndn_options['name'] = sys.argv[1]
        if sys.argv[2].upper()[0] == 'D':
            self.ndn_options['type'] = 'data'
        if self.dirname == 'ndn_adap':
            self.route_stack = None       
            routes = eval(sys.argv[3])  
            num_routes = len(routes) 
            for route in routes:        
                ndn_srp = NDNSRPStack(bos=(1 if num_routes == 1 else 0),
                    mcast_flag=1 if str(route[0]).upper()[0] == 'M' or str(route[0]) == '1' else 0, mcast_port=int(route[1]))
                self.route_stack = self.route_stack / ndn_srp if self.route_stack else ndn_srp
                num_routes -= 1            
        else:
            self.parse_dst_ip_hw(sys.argv[3])       
        print sys.argv
        self.parse_options(sys.argv[4:])                             
     
    def get_wait_time(self):        
        if (self.pkts_num <= self.pkts_slow_send['begin']) or (self.pkts_num >= self.pkts_slow_send['end']):
            return 1.0 * self.mem_max_pkts / self.pkts_slow_send['pps']
        else:
            return 0

    def get_pkt_payload(self):
        # create NDN packet
        self.ndn_options['content'] = str(datetime.now())
        return NDN.create(self.ndn_options)

    def get_pkt_ndn_adap(self):
        pkts = []        
        # create NDN ADAP
        for idx in xrange(0, self.mem_max_pkts):
            pkt = NDNADAP(id=self.ndn_options['name'], int_data_flag=(0 if self.ndn_options['type'] == 'interest' else 1) )              
            # add src route stack
            pkt = pkt / self.route_stack
            pkts.append(pkt)
        return pkts

    def get_pkt_normal(self):
        pkts = []
        for idx in xrange(0, self.mem_max_pkts):                        
            pkt = Ether(src=self.hw_addr_src, dst=self.hw_addr_dst )
            pkt = pkt / IP(dst=self.ip_addr_dst) / UDP(sport=random.randint(49152,65535))             
            pkts.append(pkt)
        return pkts

    def send_pkt(self):
        print 'SEND - STARTED    - TEST MODE'              
        pkt = self.get_pkt()[0]
        pkt = pkt / self.get_pkt_payload()
        self.socket.send(pkt) 
        self.pkts_num += 1
        self.pkts_len += len(pkt)    
        pkt.show2()
        print 'SEND - TERMINATED - TEST MODE'     

    def handle_pkt(self):
        print 'SEND - STARTED'      
        # if self.sync_timer:
        #     self.sync_timer['timer'].start()
        while (datetime.now() - self.simulation_start).total_seconds() < self.total_simulation_time:        
            # self.send_lock.acquire()
            # print '[main thread] get pkt'
            for pkt in self.get_pkt():
                # print '[main thread] send pkt'
                pkt = pkt / self.get_pkt_payload()
                self.socket.send(pkt) 
                self.pkts_num += 1
                self.pkts_len += len(pkt)      
            wait_time = self.get_wait_time()
            # print wait_time
            time.sleep(wait_time) 
            # self.send_lock.release()
        print 'SEND - TERMINATED'     

    def run(self):
        print ' '
        print 'GENERATING PACKETS ...'                
        self.simulation_start = datetime.now()
        if self.test_mode:
            self.send_pkt()        
        else:
            self.handle_pkt()        
        self.exit_gracefully(0, 0)

# def main():        
#     print "sending on interface %s" % (iface)
#     # create NDN ADAP
#     pkt = NDNADAP(id=content_id, int_data_flag=int_data)  
#     # create source route stack
#     num_routes = len(route_stack)        
#     for route in route_stack:        
#         pkt = pkt / NDNSRPStack(bos=(1 if num_routes == 1 else 0),
#             mcast_flag=1 if str(route[0]).upper()[0] == 'M' or str(route[0]) == '1' else 0, mcast_port=int(route[1]))
#         num_routes -= 1
#     # create NDN packet
#     pkt =  pkt / NDN.create(options)
#     pkt.show2()
#     print ' '
#     print ' '
#     print ' -----  PACOTE TESTE ENVIADO  ------ '
#     print ' '
#     sendp(pkt, iface=iface, verbose=False)


if __name__ == '__main__':
    simulation = Simulation()    
    simulation.run()
