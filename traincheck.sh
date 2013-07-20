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
         echo "Zug von $from nach $target ($train um $time Uhr von Gleis $platform) hat $delay Minute(n) Verspaetung! Grund: $reason" >> $ZUGCHECKHOME/traincheck.log
         # DELAY FOUND - SWITCH ON THE LED!
         /bin/led-ctrl filesystem_mount_failure
       else 
         echo "Zug von $from nach $target ($train um $time Uhr von Gleis $platform) ist puenktlich!" >> $ZUGCHECKHOME/traincheck.log
     fi
     
done < $ZUGCHECKHOME/mytrains.xml

# MAKE SURE THAT YOUR MAILER IS CONFIGURED PROPERLY!
mailer -s "Aktueller Zugcheck" -i $ZUGCHECKHOME/traincheck.log -r

# CLEAN UP
rm $ZUGCHECKHOME/forward.txt
rm $ZUGCHECKHOME/return.txt

rm $ZUGCHECKHOME/mytrains.xml

