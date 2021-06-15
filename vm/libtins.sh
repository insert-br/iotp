#!/bin/bash
sudo apt-get update
sudo apt-get install -y git
git clone https://github.com/mfontanini/libtins.git libtins
git pull
git submodule update --init --recursive
sudo apt-get install -y autoconf automake make build-essential libpcap-dev libssl-dev cmake
cd libtins
mkdir -p build
cd build
cmake ../ -DLIBTINS_ENABLE_CXX11=1
make -j4
sudo make -j4 install
sudo ldconfig
make -j4 tests
make -j4 test
cd ../..
sudo rm -r libtins/
# use the following to compile code with libtins
#    g++ app.cpp -o app -ltins
