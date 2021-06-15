BUILD_DIR = build
PCAP_DIR = pcaps
LOG_DIR = logs

TOPO = topology.json
P4C = p4c-bm2-ss
RUN_SCRIPT = ../../utils/run_exercise.py

source := $(wildcard *.p4)
outfile := $(source:.p4=.json)

compiled_json := $(BUILD_DIR)/$(outfile)

# Define NO_P4 to start BMv2 without a program
ifndef NO_P4
run_args += -j $(compiled_json)
endif

# Set BMV2_SWITCH_EXE to override the BMv2 target
ifdef BMV2_SWITCH_EXE
run_args += -b $(BMV2_SWITCH_EXE)
endif

all: run

run: build stop disable_ipv6
	echo ''
	sudo python $(RUN_SCRIPT) -t $(TOPO) $(run_args)

run_ipv6: build stop enable_ipv6
	echo ''
	sudo python $(RUN_SCRIPT) -t $(TOPO) $(run_args)

stop: 
	sudo mn -c
	sudo killall -q -s KILL firefox wireshark telnet iperf ; echo ''

build: dirs $(compiled_json) 

$(BUILD_DIR)/%.json: %.p4
	$(P4C) --p4v 16 $(P4C_ARGS) -o $@ $^

dirs: clean
	mkdir -p $(BUILD_DIR) $(PCAP_DIR) $(LOG_DIR)

clean: stop
	sudo rm -rf $(BUILD_DIR)/* $(PCAP_DIR)/* $(LOG_DIR)/* 	

disable_ipv6:
	sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
	sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1

enable_ipv6:
	sudo sysctl -w net.ipv6.conf.all.disable_ipv6=0	               
	sudo sysctl -w net.ipv6.conf.default.disable_ipv6=0
