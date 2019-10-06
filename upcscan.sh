#!/bin/bash
# -----------------------------------------------------------------------------
# Configure these parameters to suit your network
# 	Network ID: Get it at http://www.cablecom.ch/index/checksetupid.htm
#	Frequency:  Frequency of initial transponder in Hz
#	Modulation: Modulation (mostly QAM256)
#	Symbolrate: Symbolrate in (for cable: 6900)
#	Device:	    Adapter to use (/dev/dvb/adapterX)
#
PARM_NETWORKID=43064
PARM_FREQUENCY=306000000
PARM_MODULATION=64
PARM_SYMBOLRATE=6900
PARM_DVBDEVICE=0
# -----------------------------------------------------------------------------
# Don't change anything below this line
# -----------------------------------------------------------------------------

trap quit INT

quit() {
	kill ${DVBTUNEPID} 2>/dev/null
	killall dvbsnoop   2>/dev/null
	exit
}

# Tune to initial transponder
if [ -z $1 ]; then
	dvbtune -f ${PARM_FREQUENCY} \
		-c ${PARM_DVBDEVICE} \
		-qam ${PARM_MODULATION} \
		-s ${PARM_SYMBOLRATE} -m &>/dev/null &
	DVBTUNEPID=$!
fi

# Initialize parameters
NID=0
TID=0
FREQ=0
MOD=0
SR=0
FIRSTTID=0

# Get transponder ID, frequency, modulation
while read LINE; do
	TMP=`echo ${LINE} | sed -n -e "s/^Network_ID: \([0-9]*\) .*$/\1/p"`
	if [ ${TMP} ]; then
		echo "Network ID: ${TMP}" >&2
		NID=${TMP}
		continue
	fi
	if [ ${NID} -ne ${PARM_NETWORKID} ]; then
		continue
	fi
  
	TMP=`echo ${LINE} | sed -n -e "s/^Transport_stream_ID: \([0-9]*\) .*$/\1/p"`
	if [ ${TMP} ]; then
		TID=${TMP}
		if [ ${FIRSTTID} -eq ${TID} ]; then
			break
		fi
		if [ ${FIRSTTID} -eq 0 ]; then
			FIRSTTID=${TID};
		fi
		continue
	fi

	TMP=`echo ${LINE} | sed -n -e "s/^Frequency: [0-9]* (= \([0-9]*\)\.\([0-9]*\)[0-9] MHz).*$/\1\2/p"`
	if [ ${TMP} ]; then
		FREQ="${TMP}"
		continue
	fi

	TMP=`echo ${LINE} | sed -n -e "s/^Symbol_rate: [0-9]* (= \([0-9]*\)\.\([0-9]*\)[0-9]).*$/\1\2/p"`
	if [ ${TMP} ]; then
		SR="${TMP}"
		continue
	fi

	TMP=`echo ${LINE} | sed -n -e "s/^Modulation .* \[= \([0-9]*\)\ QAM\].*$/\1/p"`
	if [ ${TMP} ]; then
		MOD=${TMP}
		continue
	fi

	TMP=`echo ${LINE} | sed -n -e "s/^FEC_inner: \([0-9]*\) .*$/\1/p"`
	if [ ${TMP} ]; then
		TIDS[$TID]="${FREQ}:M${MOD}:C:${SR}"
		echo "$TID: ${TIDS[$TID]}" >&2
	fi
done < <(dvbsnoop -nph 0x10 -buffersize 10240 \
	          -adapter $PARM_DVBDEVICE \
 	| grep -E "(Network_ID|Transport_stream_ID|Frequency|Symbol_rate|Modulation|FEC_inner)")


# Initialize parameters once again
FIRSTPID=0
PID=0
TID=0
SIG=""
NID=0

# Find out Service_ID->Service_Name mapping here
while read LINE; do
	TMP=`echo ${LINE} | sed -n -e "s/^Service_id: \([0-9]*\) .*$/\1/p"`
	if [ ${TMP} ]; then
		SID=${TMP}
		PID=${TMP}
		if [ ${FIRSTPID} -eq ${PID} ]; then
			break
		fi
		if [ ${FIRSTPID} -eq 0 ]; then
			FIRSTPID=${PID}
		fi
		continue
  	fi

	TMP=`echo ${LINE} | sed -n -e "s/^Free_CA_mode: \([0-9]*\) .*$/\1/p"`
	if [ ${TMP} ]; then
		CAID=${TMP}
	fi

	TMP=`echo ${LINE} | sed -n -e "s/^service_type: \([0-9]*\) .*$/\1/p"`
	if [ ${TMP} ]; then
		TYPE=${TMP}
	fi

	TMP=`echo ${LINE} | sed -n -e "s/^service_provider_name: \"\(.*\)\" .*$/\1/p"`
	if [ ${TMP} ]; then
		SPN=${TMP}
	fi

	TMP=`echo ${LINE} | sed -n -e "s/^Original_network_ID: \([0-9]*\) .*$/\1/p"`
	if [ ${TMP} ]; then
		NID=${TMP}
	fi

	TMP=`echo ${LINE} | sed -n -e "s/^Service_name: \"\(.*\)\" .*$/\1/p"`
	if [ "${TMP}" ]; then
		SIG=${TMP}
		if [ ! -z ${TIDS[${TID}]} ]; then
			# set following IDs to 0 - they will be updated by vdr later
			RID=0
			VPID=0
			APID=0
			TPID=0
			echo "${SIG};${SPN}:${TIDS[${TID}]}:${VPID}:${APID}:${TPID}:${CAID}:${SID}:${NID}:${TID}:${RID}"
		fi
		continue
  	fi

	TMP=`echo ${LINE} | sed -n -e "s/^Transport_Stream_ID: \(.*\) .*$/\1/p"`
	if [ "${TMP}" ]; then
		TID=${TMP}
		continue
	fi
done < <(dvbsnoop -nph 0x11 -buffersize 10240 \
	 	  -adapter ${PARM_DVBDEVICE} \
	 | grep -E "(Service_id|Service_name|Transport_Stream_ID|service_provider_name|Free_CA_mode|service_type|Original_network_ID)")

kill ${DVBTUNEPID} 2>/dev/null

