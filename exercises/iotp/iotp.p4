/* -*- P4_16 -*- */
#include <core.p4>
#include <v1model.p4>

typedef bit<9>  egressSpec_t;
typedef bit<48> macAddr_t;
typedef bit<16> etherType_t;
// typedef bit<32> ipv4Addr_t;
// typedef bit<16> portNumber_t;

// general IOTP header structure
typedef bit<9>  serviceId_t;
typedef bit<14> dataCount_t;
typedef bit<16> iotpType_t;
typedef bit<48> iotpDelay_t;
typedef bit<64> iotpData_t;

// internal registers used to accumulate IOTP data
typedef bit<32> dataCountReg_t;
// size of the half of iotp data
typedef bit<32> iotpDataHalfReg_t;
// size of half of the iotp delay
typedef bit<32> iotpDelayHalfReg_t;

// max hash ID used to store iotp data
typedef bit<32> iotpHashId_t;

// const etherType_t ETYPE_VLAN = 0x8100;
// const etherType_t ETYPE_IPV4 = 0x0800;
// const etherType_t ETYPE_IPV6 = 0x86DD;
// const etherType_t ETYPE_IOTP = 0xFA00;
const iotpType_t  ITYPE_IOTP = 0xFA00;

// TCP/UDP port used to transport IOTP
// const portNumber_t IOTP_PORT = 60000;

// P4 has a internal register limit of 200KB, so we may not store
// more than 25600 data blocks of IOTP inside P4 memory

// the amount of IOTP data blocks that fits a MTU of the network
// (For Ethernet: (1500 - 94)/8 )
const bit<32> IOTP_MTU_DATA_BLK = 50;
// max ID of the IOTP protocol
const bit<32> IOTP_MAX_ID = 512;
// MAX size of the IOTP register = Link MTU
const bit<32> IOTP_MAX_DATA_BLK = IOTP_MTU_DATA_BLK * IOTP_MAX_ID;

// error { InvalidIPv4Header }

/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/

header ethernet_t {
    macAddr_t   dstAddr;
    macAddr_t   srcAddr;
    etherType_t etherType;
}

// header ipv4_t {
//     bit<4>    version;
//     bit<4>    ihl;
//     bit<8>    diffserv;
//     bit<16>   totalLen;
//     bit<16>   identification;
//     bit<3>    flags;
//     bit<13>   fragOffset;
//     bit<8>    ttl;
//     bit<8>    protocol;
//     bit<16>   hdrChecksum;
//     ipv4Addr_t srcAddr;
//     ipv4Addr_t dstAddr;
// }

// header ipv4_options_t {    
//     varbit<320> options;
// }

// header tcp_t {
//     portNumber_t srcPort;
//     portNumber_t dstPort;
//     bit<32> seqNo;
//     bit<32> ackNo;
//     bit<4>  dataOffset;
//     bit<3>  res;
//     bit<3>  ecn;
//     bit<6>  ctrl;
//     bit<16> window;
//     bit<16> checksum;
//     bit<16> urgentPtr;
// }

// header udp_t {
//     portNumber_t srcPort;
//     portNumber_t dstPort;
//     bit<16> len;    
//     bit<16> checksum;    
// }

// TCP/IP 54 B + IPv4 options 40 B = 94 B. 
// UDP/IP 42 B + IPv4 options 40 B = 82 B. 

header iotp_t {
    serviceId_t id;
    dataCount_t count;
    iotpDelay_t delay;
    bit<1> flags;
    iotpType_t  iotpType;
}

header iotp_data_t {
    iotpData_t data;    
}

struct metadata {
    dataCountReg_t iotp_count;
}

struct headers {
    // ipv4_t         ipv4;
    // ipv4_options_t ipv4_options;
    // tcp_t          tcp;
    // udp_t          udp;
    iotp_t         iotp;
    ethernet_t     ethernet;
    iotp_data_t[IOTP_MTU_DATA_BLK] iotp_data;
}

/*************************************************************************
*********************** P A R S E R  ***********************************
*************************************************************************/

parser MyParser(packet_in packet,
                out headers hdr,
                inout metadata meta,
                inout standard_metadata_t standard_metadata) {

    state start {
        transition parse_iotp;
    }

    state parse_iotp {
        packet.extract(hdr.iotp);
        meta.iotp_count = (dataCountReg_t) hdr.iotp.count;
        transition select(hdr.iotp.iotpType) {
            ITYPE_IOTP: parse_ethernet;
            default: accept;
        }
    }

    state parse_ethernet {
        packet.extract(hdr.ethernet);
        transition select(hdr.iotp.count) {            
            0: accept;
            default: parse_iotp_data;
        }
    }

    state parse_iotp_data {
        packet.extract(hdr.iotp_data.next);
        meta.iotp_count = meta.iotp_count - 1;
        transition select(meta.iotp_count) {
            0: accept; 
            default: parse_iotp_data; // This creates a loop
        }
    }

    // state parse_ipv4 {
    //     packet.extract(hdr.ipv4);
    //     verify(hdr.ipv4.ihl >= 5, error.InvalidIPv4Header);        
    //     transition select(hdr.ipv4.ihl) {
    //         5: parse_ipv4_dispatch;
    //         default: parse_ipv4_options;
    //     }
    // }

    // state parse_ipv4_options {
    //     packet.extract(hdr.ipv4_options, (bit<32>) ( ((bit<16>) hdr.ipv4.ihl - 5) * 32 ));
    //     transition parse_ipv4_dispatch;
    // }

    // state parse_ipv4_dispatch {
    //     transition select(hdr.ipv4.protocol) {
    //         6:  parse_tcp;
    //         17: parse_udp;
    //         default: accept;
    //     }
    // }

    // state parse_tcp {
    //     packet.extract(hdr.tcp);
    //     transition select(hdr.tcp.dstPort) {
    //         IOTP_PORT: parse_iotp;
    //         default: accept;
    //     }
    // }

    // state parse_udp {
    //     packet.extract(hdr.udp);
    //     transition select(hdr.udp.dstPort) {
    //         IOTP_PORT: parse_iotp;
    //         default: accept;
    //     }
    // }    

}

/*************************************************************************
************   C H E C K S U M    V E R I F I C A T I O N   *************
*************************************************************************/

control MyVerifyChecksum(inout headers hdr, inout metadata meta) {   
    apply {  }
}

/*************************************************************************
**************  I N G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyIngress(inout headers hdr,
                  inout metadata meta,
                  inout standard_metadata_t standard_metadata) {    
    
    register<dataCountReg_t>(IOTP_MAX_ID) reg_iotp_count;
    
    register<iotpDataHalfReg_t>(IOTP_MAX_DATA_BLK) reg_iotp_data_low;
    register<iotpDataHalfReg_t>(IOTP_MAX_DATA_BLK) reg_iotp_data_high;        

    register<iotpDelayHalfReg_t>(IOTP_MAX_ID*2) reg_delay_low;
    register<iotpDelayHalfReg_t>(IOTP_MAX_ID*2) reg_delay_high;

    action drop() {
        mark_to_drop();
    }        

    @atomic
    action save_accdelay() {        
        bit<32> id_hash = ((bit<32>) hdr.iotp.id) + IOTP_MAX_ID;
        iotpDelayHalfReg_t acc_delay_low;
        iotpDelayHalfReg_t acc_delay_high;
        iotpDelay_t acc_delay;
        reg_delay_low.read(acc_delay_low, id_hash);
        reg_delay_high.read(acc_delay_high, id_hash);
        acc_delay = (acc_delay_high[23:0] ++ acc_delay_low[23:0]) + hdr.iotp.delay;
        reg_delay_low.write(id_hash, (bit<32>) acc_delay[23:0]);
        reg_delay_high.write(id_hash, (bit<32>) acc_delay[47:24]);  
    }

    @atomic
    action read_accdelay(out iotpDelay_t acc_delay) {        
        bit<32> id_hash = ((bit<32>) hdr.iotp.id) + IOTP_MAX_ID;
        iotpDelayHalfReg_t acc_delay_low;
        iotpDelayHalfReg_t acc_delay_high;
        reg_delay_low.read(acc_delay_low, id_hash);
        reg_delay_high.read(acc_delay_high, id_hash);
        acc_delay = acc_delay_high[23:0] ++ acc_delay_low[23:0];        
    }

    @atomic
    action save_start_time() {        
        reg_delay_low.write((bit<32>) hdr.iotp.id, (bit<32>) standard_metadata.ingress_global_timestamp[23:0]);
        reg_delay_high.write((bit<32>) hdr.iotp.id, (bit<32>) standard_metadata.ingress_global_timestamp[47:24]);  
    }

    @atomic
    action read_start_time(out iotpDelay_t start_time) {        
        iotpDelayHalfReg_t iotp_start_low;
        iotpDelayHalfReg_t iotp_start_high;
        reg_delay_low.read(iotp_start_low, (bit<32>) hdr.iotp.id);
        reg_delay_high.read(iotp_start_high, (bit<32>) hdr.iotp.id);
        start_time = iotp_start_high[23:0] ++ iotp_start_low[23:0];
    }

    action iotp_get_hash(out iotpHashId_t iotp_hash_id, in dataCountReg_t iotp_count){
        iotp_hash_id = iotp_count + (IOTP_MTU_DATA_BLK * ((bit<32>) hdr.iotp.id));                
    }

    @atomic
    action iotp_data_read(out iotp_data_t iotp_data, inout iotpHashId_t iotp_hash_id){
        iotpDataHalfReg_t iotp_data_low;
        iotpDataHalfReg_t iotp_data_high;
        reg_iotp_data_low.read(iotp_data_low, iotp_hash_id);
        reg_iotp_data_high.read(iotp_data_high, iotp_hash_id);
        iotp_data.setValid();
        iotp_data.data = iotp_data_high ++ iotp_data_low;
        meta.iotp_count = meta.iotp_count-1;          
        iotp_hash_id = iotp_hash_id + 1;
    }

    @atomic
    action iotp_data_store(in iotp_data_t iotp_data, inout iotpHashId_t iotp_hash_id){
        reg_iotp_data_low.write(iotp_hash_id, iotp_data.data[31:0]);
        reg_iotp_data_high.write(iotp_hash_id, iotp_data.data[63:32]);    
        meta.iotp_count = meta.iotp_count + 1;
        iotp_hash_id = iotp_hash_id + 1;      
    }

    action eth_forward(egressSpec_t port) {
        standard_metadata.egress_spec = port;        
    }

    action broadcast() {
        standard_metadata.mcast_grp = 1;        
    }

    table eth_tbl_forward {
        key = {
            hdr.ethernet.dstAddr: exact;
        }
        actions = {
            eth_forward;
            broadcast;
            drop;
        }
        size = 1024;
        default_action = drop();
    }    

    table iotp_tbl_send {
        key = {
            hdr.iotp.id: range;
            meta.iotp_count: range;
            hdr.iotp.flags: range;
        }
        actions = {
            NoAction;
            drop;
        }
        size = IOTP_MAX_ID;
        default_action = drop();
    }
    
    apply {                             
        dataCountReg_t iotp_count_agg;
        iotpHashId_t iotp_hash_id; 
        reg_iotp_count.read(meta.iotp_count, (bit<32>) hdr.iotp.id);
        iotp_get_hash(iotp_hash_id, meta.iotp_count);
        // set the limit of the remaining space available in the registers
        iotp_count_agg = ((dataCountReg_t) hdr.iotp.count) + meta.iotp_count;
        if (iotp_count_agg > IOTP_MTU_DATA_BLK){
            iotp_count_agg = IOTP_MTU_DATA_BLK;
        }
        // save delay data - this reduces IOTP's switch speed by 25 %
        save_accdelay(); 

        // store received IOTP data inside registers            
        if (meta.iotp_count < iotp_count_agg){  
            if (meta.iotp_count == 0){
                save_start_time();
            }
            iotp_data_store(hdr.iotp_data[0], iotp_hash_id);              
            if (meta.iotp_count < iotp_count_agg){  
                iotp_data_store(hdr.iotp_data[1], iotp_hash_id);  
                if (meta.iotp_count < iotp_count_agg){  
                    iotp_data_store(hdr.iotp_data[2], iotp_hash_id);  
                    if (meta.iotp_count < iotp_count_agg){  
                        iotp_data_store(hdr.iotp_data[3], iotp_hash_id);  
                        if (meta.iotp_count < iotp_count_agg){  
                            iotp_data_store(hdr.iotp_data[4], iotp_hash_id);                              
                            if (meta.iotp_count < iotp_count_agg){
                                iotp_data_store(hdr.iotp_data[5], iotp_hash_id);  
                                if (meta.iotp_count < iotp_count_agg){  
                                    iotp_data_store(hdr.iotp_data[6], iotp_hash_id);  
                                    if (meta.iotp_count < iotp_count_agg){  
                                        iotp_data_store(hdr.iotp_data[7], iotp_hash_id);  
                                        if (meta.iotp_count < iotp_count_agg){
                                            iotp_data_store(hdr.iotp_data[8], iotp_hash_id);  
                                            if (meta.iotp_count < iotp_count_agg){  
                                                iotp_data_store(hdr.iotp_data[9], iotp_hash_id);  
                                            }
                                        }
                                    }
                                }
                            } 
                        }
                    }
                }
            }
        }               

        if (meta.iotp_count < iotp_count_agg){  
            iotp_data_store(hdr.iotp_data[10], iotp_hash_id);  
            if (meta.iotp_count < iotp_count_agg){
                iotp_data_store(hdr.iotp_data[11], iotp_hash_id);  
                if (meta.iotp_count < iotp_count_agg){  
                    iotp_data_store(hdr.iotp_data[12], iotp_hash_id);  
                    if (meta.iotp_count < iotp_count_agg){
                        iotp_data_store(hdr.iotp_data[13], iotp_hash_id);  
                        if (meta.iotp_count < iotp_count_agg){  
                            iotp_data_store(hdr.iotp_data[14], iotp_hash_id);  
                            if (meta.iotp_count < iotp_count_agg){  
                                iotp_data_store(hdr.iotp_data[15], iotp_hash_id);  
                                if (meta.iotp_count < iotp_count_agg){
                                    iotp_data_store(hdr.iotp_data[16], iotp_hash_id);  
                                    if (meta.iotp_count < iotp_count_agg){  
                                        iotp_data_store(hdr.iotp_data[17], iotp_hash_id);
                                        if (meta.iotp_count < iotp_count_agg){
                                            iotp_data_store(hdr.iotp_data[18], iotp_hash_id);
                                            if (meta.iotp_count < iotp_count_agg){  
                                                iotp_data_store(hdr.iotp_data[19], iotp_hash_id);  
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        if (meta.iotp_count < iotp_count_agg){  
            iotp_data_store(hdr.iotp_data[20], iotp_hash_id);  
            if (meta.iotp_count < iotp_count_agg){  
                iotp_data_store(hdr.iotp_data[21], iotp_hash_id);  
                if (meta.iotp_count < iotp_count_agg){  
                    iotp_data_store(hdr.iotp_data[22], iotp_hash_id);  
                    if (meta.iotp_count < iotp_count_agg){  
                        iotp_data_store(hdr.iotp_data[23], iotp_hash_id);  
                        if (meta.iotp_count < iotp_count_agg){  
                            iotp_data_store(hdr.iotp_data[24], iotp_hash_id);  
                            if (meta.iotp_count < iotp_count_agg){
                                iotp_data_store(hdr.iotp_data[25], iotp_hash_id);  
                                if (meta.iotp_count < iotp_count_agg){
                                    iotp_data_store(hdr.iotp_data[26], iotp_hash_id);  
                                    if (meta.iotp_count < iotp_count_agg){
                                        iotp_data_store(hdr.iotp_data[27], iotp_hash_id);
                                        if (meta.iotp_count < iotp_count_agg){
                                            iotp_data_store(hdr.iotp_data[28], iotp_hash_id);
                                            if (meta.iotp_count < iotp_count_agg){
                                                iotp_data_store(hdr.iotp_data[29], iotp_hash_id);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }        

        if (meta.iotp_count < iotp_count_agg){
            iotp_data_store(hdr.iotp_data[30], iotp_hash_id);
            if (meta.iotp_count < iotp_count_agg){
                iotp_data_store(hdr.iotp_data[31], iotp_hash_id);
                if (meta.iotp_count < iotp_count_agg){  
                    iotp_data_store(hdr.iotp_data[32], iotp_hash_id);  
                    if (meta.iotp_count < iotp_count_agg){  
                        iotp_data_store(hdr.iotp_data[33], iotp_hash_id);  
                        if (meta.iotp_count < iotp_count_agg){  
                            iotp_data_store(hdr.iotp_data[34], iotp_hash_id);  
                            if (meta.iotp_count < iotp_count_agg){  
                                iotp_data_store(hdr.iotp_data[35], iotp_hash_id);
                                if (meta.iotp_count < iotp_count_agg){  
                                    iotp_data_store(hdr.iotp_data[36], iotp_hash_id);  
                                    if (meta.iotp_count < iotp_count_agg){
                                        iotp_data_store(hdr.iotp_data[37], iotp_hash_id);
                                        if (meta.iotp_count < iotp_count_agg){
                                            iotp_data_store(hdr.iotp_data[38], iotp_hash_id);
                                            if (meta.iotp_count < iotp_count_agg){  
                                                iotp_data_store(hdr.iotp_data[39], iotp_hash_id);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        if (meta.iotp_count < iotp_count_agg){  
            iotp_data_store(hdr.iotp_data[40], iotp_hash_id);
            if (meta.iotp_count < iotp_count_agg){  
                iotp_data_store(hdr.iotp_data[41], iotp_hash_id);  
                if (meta.iotp_count < iotp_count_agg){  
                    iotp_data_store(hdr.iotp_data[42], iotp_hash_id);  
                    if (meta.iotp_count < iotp_count_agg){  
                        iotp_data_store(hdr.iotp_data[43], iotp_hash_id);  
                        if (meta.iotp_count < iotp_count_agg){  
                            iotp_data_store(hdr.iotp_data[44], iotp_hash_id);
                            if (meta.iotp_count < iotp_count_agg){  
                                iotp_data_store(hdr.iotp_data[45], iotp_hash_id);  
                                if (meta.iotp_count < iotp_count_agg){  
                                    iotp_data_store(hdr.iotp_data[46], iotp_hash_id);
                                    if (meta.iotp_count < iotp_count_agg){
                                        iotp_data_store(hdr.iotp_data[47], iotp_hash_id);  
                                        if (meta.iotp_count < iotp_count_agg){  
                                            iotp_data_store(hdr.iotp_data[48], iotp_hash_id);
                                            if (meta.iotp_count < iotp_count_agg){  
                                                iotp_data_store(hdr.iotp_data[49], iotp_hash_id);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // send the accumulated IOTP data to the gateway
        switch (iotp_tbl_send.apply().action_run){
            drop: {
                // update the switch accumulator counter 
                reg_iotp_count.write((bit<32>) hdr.iotp.id, iotp_count_agg);     
            }
            default: {
                iotpDelay_t start_time;
                iotpDelay_t acc_delay;
                iotpHashId_t iotp_hash_id_send;
                iotp_get_hash(iotp_hash_id_send, 0);
                read_start_time(start_time);
                read_accdelay(acc_delay);
                // set the IOTP header counter            
                hdr.iotp.count = (dataCount_t) meta.iotp_count;
                hdr.iotp.delay = acc_delay + (standard_metadata.ingress_global_timestamp - start_time);
                // ((iotpDelay_t) standard_metadata.deq_timedelta)            

                if (meta.iotp_count > 0){  
                    iotp_data_read(hdr.iotp_data[0], iotp_hash_id_send);
                    if (meta.iotp_count > 0){  
                        iotp_data_read(hdr.iotp_data[1], iotp_hash_id_send);
                        if (meta.iotp_count > 0){  
                            iotp_data_read(hdr.iotp_data[2], iotp_hash_id_send);  
                            if (meta.iotp_count > 0){  
                                iotp_data_read(hdr.iotp_data[3], iotp_hash_id_send);  
                                if (meta.iotp_count > 0){  
                                    iotp_data_read(hdr.iotp_data[4], iotp_hash_id_send);
                                    if (meta.iotp_count > 0){  
                                        iotp_data_read(hdr.iotp_data[5], iotp_hash_id_send);  
                                        if (meta.iotp_count > 0){  
                                            iotp_data_read(hdr.iotp_data[6], iotp_hash_id_send);  
                                            if (meta.iotp_count > 0){  
                                                iotp_data_read(hdr.iotp_data[7], iotp_hash_id_send);  
                                                if (meta.iotp_count > 0){  
                                                    iotp_data_read(hdr.iotp_data[8], iotp_hash_id_send);  
                                                    if (meta.iotp_count > 0){  
                                                        iotp_data_read(hdr.iotp_data[9], iotp_hash_id_send);
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                if (meta.iotp_count > 0){  
                    iotp_data_read(hdr.iotp_data[10], iotp_hash_id_send);
                    if (meta.iotp_count > 0){  
                        iotp_data_read(hdr.iotp_data[11], iotp_hash_id_send);  
                        if (meta.iotp_count > 0){  
                            iotp_data_read(hdr.iotp_data[12], iotp_hash_id_send);  
                            if (meta.iotp_count > 0){  
                                iotp_data_read(hdr.iotp_data[13], iotp_hash_id_send);  
                                if (meta.iotp_count > 0){  
                                    iotp_data_read(hdr.iotp_data[14], iotp_hash_id_send);  
                                    if (meta.iotp_count > 0){  
                                        iotp_data_read(hdr.iotp_data[15], iotp_hash_id_send);  
                                        if (meta.iotp_count > 0){  
                                            iotp_data_read(hdr.iotp_data[16], iotp_hash_id_send);  
                                            if (meta.iotp_count > 0){  
                                                iotp_data_read(hdr.iotp_data[17], iotp_hash_id_send);  
                                                if (meta.iotp_count > 0){
                                                    iotp_data_read(hdr.iotp_data[18], iotp_hash_id_send);  
                                                    if (meta.iotp_count > 0){
                                                        iotp_data_read(hdr.iotp_data[19], iotp_hash_id_send);  
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                if (meta.iotp_count > 0){  
                    iotp_data_read(hdr.iotp_data[20], iotp_hash_id_send);
                    if (meta.iotp_count > 0){  
                        iotp_data_read(hdr.iotp_data[21], iotp_hash_id_send);  
                        if (meta.iotp_count > 0){  
                            iotp_data_read(hdr.iotp_data[22], iotp_hash_id_send);  
                            if (meta.iotp_count > 0){  
                                iotp_data_read(hdr.iotp_data[23], iotp_hash_id_send);  
                                if (meta.iotp_count > 0){  
                                    iotp_data_read(hdr.iotp_data[24], iotp_hash_id_send);  
                                    if (meta.iotp_count > 0){  
                                        iotp_data_read(hdr.iotp_data[25], iotp_hash_id_send);  
                                        if (meta.iotp_count > 0){  
                                            iotp_data_read(hdr.iotp_data[26], iotp_hash_id_send);
                                            if (meta.iotp_count > 0){  
                                                iotp_data_read(hdr.iotp_data[27], iotp_hash_id_send);
                                                if (meta.iotp_count > 0){  
                                                    iotp_data_read(hdr.iotp_data[28], iotp_hash_id_send);
                                                    if (meta.iotp_count > 0){
                                                        iotp_data_read(hdr.iotp_data[29], iotp_hash_id_send);  
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                if (meta.iotp_count > 0){  
                    iotp_data_read(hdr.iotp_data[30], iotp_hash_id_send);  
                    if (meta.iotp_count > 0){  
                        iotp_data_read(hdr.iotp_data[31], iotp_hash_id_send);  
                        if (meta.iotp_count > 0){  
                            iotp_data_read(hdr.iotp_data[32], iotp_hash_id_send);  
                            if (meta.iotp_count > 0){  
                                iotp_data_read(hdr.iotp_data[33], iotp_hash_id_send);  
                                if (meta.iotp_count > 0){  
                                    iotp_data_read(hdr.iotp_data[34], iotp_hash_id_send);  
                                    if (meta.iotp_count > 0){  
                                        iotp_data_read(hdr.iotp_data[35], iotp_hash_id_send);  
                                        if (meta.iotp_count > 0){  
                                            iotp_data_read(hdr.iotp_data[36], iotp_hash_id_send);  
                                            if (meta.iotp_count > 0){  
                                                iotp_data_read(hdr.iotp_data[37], iotp_hash_id_send);  
                                                if (meta.iotp_count > 0){  
                                                    iotp_data_read(hdr.iotp_data[38], iotp_hash_id_send);  
                                                    if (meta.iotp_count > 0){  
                                                        iotp_data_read(hdr.iotp_data[39], iotp_hash_id_send);  
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                if (meta.iotp_count > 0){  
                    iotp_data_read(hdr.iotp_data[40], iotp_hash_id_send);  
                    if (meta.iotp_count > 0){  
                        iotp_data_read(hdr.iotp_data[41], iotp_hash_id_send);  
                        if (meta.iotp_count > 0){  
                            iotp_data_read(hdr.iotp_data[42], iotp_hash_id_send);  
                            if (meta.iotp_count > 0){  
                                iotp_data_read(hdr.iotp_data[43], iotp_hash_id_send);  
                                if (meta.iotp_count > 0){
                                    iotp_data_read(hdr.iotp_data[44], iotp_hash_id_send);  
                                    if (meta.iotp_count > 0){  
                                        iotp_data_read(hdr.iotp_data[45], iotp_hash_id_send);  
                                        if (meta.iotp_count > 0){  
                                            iotp_data_read(hdr.iotp_data[46], iotp_hash_id_send);  
                                            if (meta.iotp_count > 0){  
                                                iotp_data_read(hdr.iotp_data[47], iotp_hash_id_send);  
                                                if (meta.iotp_count > 0){  
                                                    iotp_data_read(hdr.iotp_data[48], iotp_hash_id_send);  
                                                    if (meta.iotp_count > 0){  
                                                        iotp_data_read(hdr.iotp_data[49], iotp_hash_id_send);  
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                // update the switch accumulator counter 
                reg_iotp_count.write((bit<32>) hdr.iotp.id, 0);    

                // forward the packet it
                if (hdr.ethernet.isValid()) {  eth_tbl_forward.apply();  }
            }
        }      
    }
}

/*************************************************************************
****************  E G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyEgress(inout headers hdr,
                 inout metadata meta,
                 inout standard_metadata_t standard_metadata) {
    apply {  }
}

/*************************************************************************
*************   C H E C K S U M    C O M P U T A T I O N   **************
*************************************************************************/

control MyComputeChecksum(inout headers  hdr, inout metadata meta) {
     apply { 
        // update_checksum(
	    //     hdr.ipv4.isValid(),
        //     { hdr.ipv4.version,
	    //       hdr.ipv4.ihl,
        //       hdr.ipv4.diffserv,
        //       hdr.ipv4.totalLen,
        //       hdr.ipv4.identification,
        //       hdr.ipv4.flags,
        //       hdr.ipv4.fragOffset,
        //       hdr.ipv4.ttl,
        //       hdr.ipv4.protocol,
        //       hdr.ipv4.srcAddr,
        //       hdr.ipv4.dstAddr },
        //     hdr.ipv4.hdrChecksum,
        //     HashAlgorithm.csum16);        
     }
}

/*************************************************************************
***********************  D E P A R S E R  *******************************
*************************************************************************/

control MyDeparser(packet_out packet, in headers hdr) {
    apply {
        packet.emit(hdr);
    }
}

/*************************************************************************
***********************  S W I T C H  *******************************
*************************************************************************/

V1Switch(
MyParser(),
MyVerifyChecksum(),
MyIngress(),
MyEgress(),
MyComputeChecksum(),
MyDeparser()
) main;
