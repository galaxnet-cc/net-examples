#!/bin/bash

#
# [ns1] --vethp--- [localhosthost] ----bridge1---vxlan1----[vxlanns]----vxlan2----bridge2----[localhost]---vethp---[ns2]
# vxlan1: 192.168.10.1->192.168.10.2:4789, will be NATed in vxlanns to 192.168.20.2->192.168.20.1:4790
# vxlan2: 192.168.20.1->192.168.20.2:4790, will be NATed in vxlanns to 192.168.10.2->192.168.10.1:4789


setupnet() {
    ip netns add ns1
    ip netns add ns2
    ip netns add nsvxlan
    brctl addbr ns1br
    brctl addbr ns2br

    ip link set ns1br up
    ip link set ns2br up
    ip netns exec ns1 ip link set lo up
    ip netns exec ns2 ip link set lo up
    ip netns exec nsvxlan ip link set lo up

    ip link add ns1link type veth peer name ns1linkp
    ip link add ns2link type veth peer name ns2linkp
    ip link add nsvxlanlink1 type veth peer name nsvxlanlink1p
    ip link add nsvxlanlink2 type veth peer name nsvxlanlink2p

    ip link set ns1link up
    ip link set ns1linkp netns ns1
    ip netns exec ns1 ip link set ns1linkp up

    ip link set ns2link up
    ip link set ns2linkp netns ns2
    ip netns exec ns2 ip link set ns2linkp up

    ip link set nsvxlanlink1 up
    ip link set nsvxlanlink1p netns nsvxlan
    ip netns exec nsvxlan ip link set nsvxlanlink1p up

    ip link set nsvxlanlink2 up
    ip link set nsvxlanlink2p netns nsvxlan
    ip netns exec nsvxlan ip link set nsvxlanlink2p up

    ip netns exec ns1 ip addr add 192.168.1.1/24 dev ns1linkp
    ip netns exec ns2 ip addr add 192.168.1.2/24 dev ns2linkp

    ip addr add 192.168.10.1/24 dev nsvxlanlink1
    ip netns exec nsvxlan ip addr add 192.168.10.2/24 dev nsvxlanlink1p

    ip addr add 192.168.20.1/24 dev nsvxlanlink2
    ip netns exec nsvxlan ip addr add 192.168.20.2/24 dev nsvxlanlink2p

    ip link add ns1cnsvxlan type vxlan id 1 dev nsvxlanlink1 remote 192.168.10.2 dstport 4789
    # use 4790 to workaround linux kernel can't support two vxlan port share same vxlan port and same vni
    ip link add ns2cnsvxlan type vxlan id 1 dev nsvxlanlink2 remote 192.168.20.2 dstport 4790
    ip link set ns1cnsvxlan up
    ip link set ns2cnsvxlan up

    brctl addif ns1br ns1link
    brctl addif ns1br ns1cnsvxlan

    brctl addif ns2br ns2link
    brctl addif ns2br ns2cnsvxlan

    ip netns exec nsvxlan iptables -t nat -A PREROUTING -p udp --dport 4789 -j DNAT --to-destination 192.168.20.1:4790
    ip netns exec nsvxlan iptables -t nat -A PREROUTING -p udp --dport 4790 -j DNAT --to-destination 192.168.10.1:4789
    ip netns exec nsvxlan iptables -t nat -A POSTROUTING -p udp -s 192.168.10.1 -j SNAT --to-source 192.168.20.2
    ip netns exec nsvxlan iptables -t nat -A POSTROUTING -p udp -s 192.168.20.1 -j SNAT --to-source 192.168.10.2
}

teardownnet() {
    ip link delete ns1link
    ip link delete ns2link
    ip link delete ns1cnsvxlan
    ip link delete ns2cnsvxlan

    ip link set ns1br down
    ip link set ns2br down
    brctl delbr ns1br
    brctl delbr ns2br

    ip netns delete ns1
    ip netns delete ns2
    ip netns delete nsvxlan
}

if [[ "$1" == "setup" ]]; then
    setupnet
elif [[ "$1" == "teardown" ]]; then
    teardownnet
else
    echo "sudo bash ./vxlan-on-samehost.sh [setup|teardown]"
fi
