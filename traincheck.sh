# ZUGCHECK - DEUTSCHE BAHN TRAIN DELAY CHECKER
#
# THIS BASH SCRIPT MAY BE DEPLOYED ON YOUR FRITZBOX OR ANY OTHER ROUTER
# USING CROND, FHEM OR ANY OTHER MEANS TO TRIGGER IT CYCLICALLY IT WILL 
# INDICATE DELAY ON YOUR DAILY TRAIN TRACKS BY REDBLINKING THE INFO-LED
# AND ADDITIONALLY BY SENDING YOU A MAIL WITH THE EXAMINED TRAINS...
# USE IT AT OWN RISK AND WITHOUT OBLIGATION FOR ANY ISSUE YOU WANT...
#
# Author: Andreas Tully
# Date: 20.07.2013

# HELPERS SECTION
TRAINDATE=`date +%d.%m.%Y`
TRAINTIME=`date +%H:%M`
TRAINDATE_TOMORROW=`date +%d.%m.%Y -D %s -d $(( $(date +%s) + 86400))`

# CONFIGURATION SECTION
ZUGCHECKHOME="/var/InternerSpeicher/USBDISK2-0-00"
FORWARDSTATION="Giessen"
FORWARDSTATIONID="8000124"
FORWARDDIRECTIONS="Frankfurt|Karlsruhe|Darmstadt"
RETURNSTATION="Frankfurt"
RETURNSTATIONID="8000105"
RETURNDIRECTIONS="Treysa|Dillenburg|Hannover|Giessen|Marburg|Siegen"
MINDELAYWARNING=5 # Minimum Delay for a warning in minutes
PRODUCTMASK=110100000 # Use ICE, IC and Regional Trains only...
PROWLKEY="" # API-Key for prowlapp.com. If set you will receive a push notification for delayed trains
NOTIFICATIONMAIL=true

### ZUGCHECK SCRIPT ###

# THE INFO LED WILL BE USED TO INDICATE DELAY BLINKING RED...

# FIRST SWITCH OFF THE LED
/bin/led-ctrl filesystem_done

echo "Traincheck running at $TRAINDATE $TRAINTIME..."

echo -e "GET http://reiseauskunft.bahn.de/bin/bhftafel.exe/dn?productsFilter=$PRODUCTMASK&boardType=dep&sTI=0&hcount=0&L=vs_java3&date=$TRAINDATE&time=$TRAINTIME&input=$FORWARDSTATIONID&start=yes" \
| nc reiseauskunft.bahn.de 80 > $ZUGCHECKHOME/forward.txt
echo -e "GET http://reiseauskunft.bahn.de/bin/bhftafel.exe/dn?productsFilter=$PRODUCTMASK&boardType=dep&sTI=0&hcount=0&L=vs_java3&date=$TRAINDATE&time=$TRAINTIME&input=$RETURNSTATIONID&start=yes" \
| nc reiseauskunft.bahn.de 80 > $ZUGCHECKHOME/return.txt

touch $ZUGCHECKHOME/traincheck.log
rm $ZUGCHECKHOME/traincheck.log

sed -e 's/<\/Journey>/ from=$FORWARDSTATION end <\/Journey>\n/g' $ZUGCHECKHOME/forward.txt | egrep $FORWARDDIRECTIONS \
 >> $ZUGCHECKHOME/mytrains.xml
sed -e 's/<\/Journey>/ from=$RETURNSTATION end <\/Journey>\n/g' $ZUGCHECKHOME/return.txt | egrep $RETURNDIRECTIONS \
 >> $ZUGCHECKHOME/mytrains.xml

unset delay
unset train
unset time
unset reason
unset target
unset platform
unset message

while read line; do
     delay=`echo $line | sed -rn 's/.* e_delay=\"([0-9]+)\".*/\1/p'`
     train=`echo $line | sed -rn 's/.* prod=\"(.*)#.*\" administration.*/\1/p'`
     time=`echo $line | sed -rn 's/.* fpTime=\"(.*)\" fpDate.*/\1/p'`
     reason=`echo $line | sed -rn 's/.* delayReason=\"(.*)\" approxDelay.*/\1/p'`
     target=`echo $line | sed -rn 's/.* targetLoc=\"(.*)\" dirnr.*/\1/p'`
     platform=`echo $line | sed -rn 's/.* platform=\"(.*)\" target.*/\1/p'`
     from=`echo $line | sed -rn 's/.* from=\"(.*)\" end.*/\1/p'`

     if [ $delay -gt $MINDELAYWARNING ]
       then 
         message =  "Zug von $from nach $target ($train um $time Uhr von Gleis $platform) hat $delay Minute(n) Verspaetung! Grund: $reason"
         echo $message >> $ZUGCHECKHOME/traincheck.log
         # DELAY FOUND - SWITCH ON THE LED!
         /bin/led-ctrl filesystem_mount_failure
         # AND PUSH NOTIFICATION TO PROWL
         if [ -n "$PROWLKEY" ]; then
            urlmessage = $(echo "$message" | sed -e 's/%/%25/g' -e 's/ /%20/g' -e 's/!/%21/g' -e 's/"/%22/g' -e 's/#/%23/g' -e 's/\$/%24/g' -e 's/\&/%26/g' -e 's/'\''/%27/g' -e 's/(/%28/g' -e 's/)/%29/g' -e 's/\*/%2a/g' -e 's/+/%2b/g' -e 's/,/%2c/g' -e 's/-/%2d/g' -e 's/\./%2e/g' -e 's/\//%2f/g' -e 's/:/%3a/g' -e 's/;/%3b/g' -e 's//%3e/g' -e 's/?/%3f/g' -e 's/@/%40/g' -e 's/\[/%5b/g' -e 's/\\/%5c/g' -e 's/\]/%5d/g' -e 's/\^/%5e/g' -e 's/_/%5f/g' -e 's/`/%60/g' -e 's/{/%7b/g' -e 's/|/%7c/g' -e 's/}/%7d/g' -e 's/~/%7e/g')
            echo -e "GET http://api.prowlapp.com/publicapi/add?apikey=$PROWLKEY&application=Traincheck&event=Zug%20versp%C3%A4tet&description=$urlmessage" \
            | nc api.prowlapp.com 80 > /dev/null
         fi
       else 
         echo "Zug von $from nach $target ($train um $time Uhr von Gleis $platform) ist puenktlich!" >> $ZUGCHECKHOME/traincheck.log
     fi
     
done < $ZUGCHECKHOME/mytrains.xml

# MAKE SURE THAT YOUR MAILER IS CONFIGURED PROPERLY!
if $NOTIFICATIONMAIL; then 
    mailer -s "Aktueller Zugcheck" -i $ZUGCHECKHOME/traincheck.log -r
fi

# CLEAN UP
rm $ZUGCHECKHOME/forward.txt
rm $ZUGCHECKHOME/return.txt

rm $ZUGCHECKHOME/mytrains.xml
