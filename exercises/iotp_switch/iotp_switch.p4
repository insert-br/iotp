/* -*- P4_16 -*- */
#include <core.p4>
#include <v1model.p4>

typedef bit<9>  egressSpec_t;
typedef bit<48> macAddr_t;
typedef bit<16> etherType_t;

/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/

header ethernet_t {
    macAddr_t   dstAddr;
    macAddr_t   srcAddr;
    etherType_t etherType;
}

struct metadata { }

struct headers {
    ethernet_t     ethernet;    
}

/*************************************************************************
*********************** P A R S E R  ***********************************
*************************************************************************/

parser MyParser(packet_in packet,
                out headers hdr,
                inout metadata meta,
                inout standard_metadata_t standard_metadata) {

    state start {
        transition parse_ethernet;
    }

    state parse_ethernet {
        packet.extract(hdr.ethernet);        
        transition accept;        
    }

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

    action drop() {
        mark_to_drop();
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
    
    apply {        
        eth_tbl_forward.apply();           
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
     apply {  }
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
