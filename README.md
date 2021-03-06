# Aleph-SIP2-mini-server
SIP2 server solution, with limited services, suitable for RFID UHF security gates etc.


The script should be run on background, ideally on boot using crontab. It has infite loop that listens of defined port.

It accepts SIP2 requests. Than calls ALEPH API (X-SERVER) that is used for gathering information. Transofrm data to SIP2 standard and returns the response

NOTE
Currently only few SIP2 are supported:
17/18 Item Information  
  supported circulation statuses in reponse:  3 - available (not loaned), 4 - charged (on regular loan), 6 - in process (on base of defined item process statuses), 10 - in transit between libraries (on base of defined patron status(es) for transfer patrons), 13 - missing (on base of defined item process statuses)
98/99 SCP (Aleph) status

93/94 login (does not require real login, always response as ok)


--The other can be implemented by adding new subs that will also call Aleph API and process the request

IMPLEMENTATION
Put it anywhere on the aleph server. Edit the file, check path to perl on first line and edit parameters of the script after mark '#initial variables' (line 42 on). Make the script executable.

For direct run in background execute as:
./sip2mini.pl '2>&1' &
In crontab for boot start use
@reboot exec {pathToScript}/sip2mini.pl 2>&1 &

Make sure that the defined port id opened on tcp using local and central firewall.


KNOWN ISSUES
I1: The script does not count and return checksum. It is prepared, but not tested.
I2: For item information request/response (17/18), the item is not checked for hold requests, if it is not located on hold shelf (SIP2 circulation status 08)

Dependencies: Perl of the Aleph distribution, Aleph min. ver. 18 with X-Server

TIP: Try SIP2 Windows graphic testing tool available at https://clcohio.org/sip-testing-tool/

Made by Matyas F. Bajger, University of Ostrava, University Library, February 2022
GNU GPL Licence

