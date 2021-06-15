#!/usr/bin/env python

from scapy.all import *
from scapy.packet import bind_layers
from scapy.fields import BitField

class Data:
    udp_base_port = 1025    
    headers = ['temp','humidity','light','volt']
    header_map, idx = {}, 0
    for header in headers:
        header_map[header] = idx
        idx += 1

class IOTPData(Packet):
    name = "IOTP Data "            
    fields_desc=[
        BitField("data", None, 64)        
    ] 
    # define whats the next layer 
    def guess_payload_class(self, payload):
        return IOTPData

class IOTP(Packet):
    name = "IOTP Packet "
    fields_desc=[
        BitField("id", 0, 9),
        BitField("count", 0, 14),
        BitField("delay", 0, 48),
        BitField("flags", 0, 1),
        BitField("type", 0, 16)
    ]     
    itype = 0xFA00    
    etype = 0xFA00    
    # define whats the next layer 
    # def guess_payload_class(self, payload):
    #     return IOTPData

# remove not used protocols from Scapy dissector
Ether.payload_guess = [({"type": 0x800}, IP)]
IP.payload_guess = [({"frag": 0, "proto": 0x11}, UDP), ({"frag": 0, "proto": 0x06}, TCP)]
UDP.payload_guess = []
TCP.payload_guess = []

# glue IOTP to TCP/UDP ports to allow Scapy to dissect it
# bind_layers( TCP, IOTP, dport=IOTP.port )
# bind_layers( UDP, IOTP, dport=IOTP.port )
# bind_layers( Ether, IOTP, type=IOTP.etype )
bind_layers( IOTP, Ether, type=IOTP.itype )
bind_layers( Ether, IOTPData, type=IOTP.etype )
