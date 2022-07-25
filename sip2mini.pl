#!/exlibris/product/bin/perl

#
#
##Script processing SIP2 requests and responses to be used with ALEPH LMS. Like SIP2 server,
##   Mini/developent version that parses only selected SIP2 requests (mind that for all of them, ALEPH API is not sufficient - do not have instruments for loans and returna)
##
##Requirements: Aleph 22/23 with RestAPI and XServer, perl cgi with below mentioned modules
##
##Input: SIP2 request
##Output: SIP2 response
##
##On the base of SIP2 request, corresponding ALEPH API is called, reponse is processes and converted to SIP2 response
##
#
#To run on background with stderr redirect to log file run:
#	nohup sip2mini.pl '2>&1' &
#
#
#Requirements:	Perl from Aleph distribution, without extra modules
#		X-Server Aleph: following API services must be granted to general WWW-X user to access in your ADM base: ill-item-by-bc, ill-get-doc-short 
#											lll-loan-info is also used, but protected by password set below
#
##by Matyas Bajger, library.osu.eu, 2022, GNU GPL License
##
#
#

use strict;
use warnings;
use utf8;
binmode(STDOUT, ":utf8");
binmode(STDIN, ":utf8");
use open qw( :std :encoding(UTF-8) ); #thhis
use Encode 'encode'; #thhis
use IO::Socket;
use Socket;
use URI::Escape;
use LWP;
use XML::Simple;
use Switch;
use CGI;
use Switch;
use POSIX qw/strftime/;
use POSIX qw/floor/;
use Data::Dumper;
# Execute anytime before the <STDIN>.
# # Causes the currently selected handle to be flushed immediately and after every print.
$| = 1;
use IO::Handle;
STDOUT->autoflush(1);
LOGFILE->autoflush(1);

#initial variables
my $listenOnPort='5330'; #Port, where SIP2 server listens
my $add_checksum='0'; #if true, the ACS responsed will also contain AY field with sequence number (always "1" value) and AZ field with checksum #TODO to be tested yet
my $adm_base="osu50"; #lower case
my $xserver_url="https://katalog.osu.cz/X"; #URL of th x-server
my $ill_item_by_bc_user=""; #aleph user with privilegies to Xserver service ill-item-by-bc. Leave empty, if the service is available without user/password (as www-x user)
my $ill_item_by_bc_pas=""; #the same - password
my $ill_loan_info_user="X-LOAN-INF"; #aleph user with privilegies to Xserver service ill-loan-info. Leave empty, if the service is available without user/password (as www-x user)
my $ill_loan_info_pas="W2sfD8PGqP"; #the same - password
my $transfer_patron='transfer patron'; #name of the patron status used for transfer between l;ibrary departments ($data_tab/pc_teb_extended.eng - BOR-STATUS)
my @in_process_status=('IP','RE'); #item process statuses (codes) as defined in Aleph for in process (returns SIP2 circulation_status 06 - in process. It is array - more codes can be defined here
my @missing_status=('MI','MP','MR','VY'); #item process statuses (codes) as defined in Aleph for missing/lost items - returns SIP2 circulation_status 12 - lost. It is array - more codes can be defined here
my $log='/exlibris/aleph/matyas/sip2/sip2mini.log'; #for writing registrations, alerts and errors
my $admin_mail='matyas.bajger@osu.cz'; #for sending errors etc.
my $debug='0'; #debug mode, sends all registrations to admin_email, not just erros


our $sip_in={}; our $sip_out={}; our $aapi_in={}; our $aapi_out={}; our $now;
unless ( open ( LOGFILE, ">>$log" ) ) {print "Error - cannot open log file $log\n"; }
binmode(LOGFILE, ":utf8");

$now=strftime "%Y%m%d-%H:%M:%S", localtime;
print LOGFILE "START - $now\n";


#kill previous executions of this daemon
my $myPID=$$;
my $pid = `ps -ef | grep 'sip2mini.pl' | grep -v grep | grep -v $myPID | awk '{print \$2}'`;
if ($pid) {
   print "Killing previous execution of sip2mini.pl with PID $pid\n";
   print LOGFILE "Killing previous execution of sip2mini.pl with PID $pid\n";
   system("kill -9 $pid");
   }


print LOGFILE "Running the daemon...\n";
#define socket
my $socket = new IO::Socket::INET (
        #LocalHost => 'localhost',
        LocalHost => 'aleph.osu.cz',
        LocalPort => $listenOnPort,
        Proto => 'tcp',
        Listen => SOMAXCONN,
       Reuse => 1
);
#setsockopt($socket, SOL_SOCKET, SO_REUSEADDR, SO_REUSEPORT, SO_KEEPALIVE, 1);
setsockopt($socket, SOL_SOCKET, SO_KEEPALIVE, 1);
$socket->autoflush(1);

exceptionError ("Could not create socket: $!n") unless $socket;
print LOGFILE "Waiting for data from the client end, listening on port $listenOnPort ...\n";

my $new_socket;
my $full_message=''; 

#infinte loop 
while(1) {
#if ( $new_socket ) {print "connected ".$new_socket->connected ."\n";} #TODO DEBUG
   unless ($new_socket) { #new connection
      $new_socket = $socket->accept();  
      }

   my $message_from_client='';
   $new_socket->recv($message_from_client,1024);

   if ( length($message_from_client)==0 ) { #when socket is open and no message is comming, the recv message may be treated as existing but zero length, start new listening
      $new_socket = $socket->accept();  
      }


   my $sip_response='no_response';
my $client_address = $new_socket->peerhost() ? $new_socket->peerhost() : 'unknown_host' ;
my $client_port = $new_socket->peerport() ? $new_socket->peerport() : 'unknown_port';
print "connection from $client_address:$client_port\n";
   #20220620
   if (! $new_socket) {
      redo if $!{ECONNREFUSED};  # Error from a previous UDP send
      exceptionError('error when receiving '.$!."\n");
      }   

print "debug message_from_client is  $message_from_client\n";
print "debug ord message_from_client is ".ord($message_from_client)."\n\n";
print "debug length is ".length($message_from_client)."\n\n";

   
   
#   if ( ord($message_from_client)==13 or ord($message_from_client)==11 or length($message_from_client) > 1  or length($message_from_client) == 0 ) { #got enter from socket or accepted whole message together (has more than 1 char)
   if ( ord($message_from_client)==13 or ord($message_from_client)==11 or length($message_from_client) > 1  ) { #got enter from socket or accepted whole message together (has more than 1 char)
      if ( length($message_from_client) > 1 ) { $full_message=$message_from_client;}
      $full_message =~ s/[\n\r]//g;
print "GOT FULL MESSAGE $full_message\n"; #DEBUG
#      if ( length($full_message)==0 ) {
#         print "WARNING full_message from socket has zero length\n"; #TODO toto do logu
#         next;
#         }
      #my($iport,$iaddr) = sockaddr_in($new_socket);
      #my $iname = gethostbyaddr($iaddr,AF_INET);
      my $iaddr = $new_socket->peerhost ? $new_socket->peerhost : 'unknown ip';
      $now=strftime "%Y%m%d-%H:%M:%S", localtime;
      print LOGFILE "$now - $iaddr - Incoming message $full_message\n";
print "$now - $iaddr - Incoming message $full_message\n";
print "full_message has length ".length($full_message)."\n";
      my $service=substr( $full_message, 0, 2);
print "service is $service\n";
      if ($service eq '17') { $sip_response = itemInformation($full_message); }
      elsif ($service eq '93') { $sip_response = ACSlogin($full_message); }
      elsif ($service eq '99') { $sip_response = ACSstatus($full_message); }
      else { exceptionError('SIP2 mini currently processes only 17-request/18-reponse (loan info), 98/99 (status), 93/94 (login), other request types are not supported, received service: '."$service");}
      if ($add_checksum) { #add checksum
         $sip_response .= 'AY1AZ'.countChecksum($sip_response);
         }
      print LOGFILE "response:\n$sip_response\n\n";
      my $sip_response_bytes = encode('UTF-8', $sip_response);
      #$new_socket->send("$sip_response") ;
      $new_socket->send("$sip_response_bytes") ;
      $full_message=''; 
      }
   else {
      $full_message .= $message_from_client;
print "full_message is $full_message\n";
      }
   }
$socket->close;

#sub for processing 17 - Item information request and returning 18
#17/18 Item Information
#       The request looks like:
#17<xact_date>[fields: AO,AB,AC]
#
#The request is very terse. AC is optional.
#
#The following response structure is for SIP2. (Version 1 of the protocol had only 6 total fields.)
#
#18<circulation_status><security_marker><fee_type><xact_date>
#[fields: CF,AH,CJ,CM,AB,AJ,BG,BH,BV,CK,AQ,AP,CH,AF,AG,+CT,+CS]
#
#Example:
#1720060110    215612AOBR1|ABno_such_barcode|
#1801010120100609    162510ABno_such_barcode|AJ|
#1720060110    215612AOBR1|AB1565921879|
#1810020120100623    171415AB1565921879|AJPerl 5 desktop reference|CK001|AQBR1|APBR1|BGBR1|CTBR3|CSQA76.73.P33V76 1996|
#The first case is with a bogus barcode. The latter shows an item with a circulation_status of 10 for in transit between libraries. The known values of circulation_status are enumerated in the spec.
#
#EXTENSIONS: The CT field for destination location and CS call number are used by Automated Material Handling systems.
#
sub itemInformation {
   my ($x)=@_;
   my $is_error=''; #if an error occured during sub processing, return response with circulation status 01 - other
   $sip_in->{service}='17';
   $sip_in->{datetime}=substr($x,2,18); #18 chars, fixed length: YYYYMMDDZZZZHHMMSS
   $sip_in->{institution} = getValueByPrefix('AO',$x);
   $sip_in->{barcode} = getValueByPrefix('AB',$x);
   $sip_in->{barcode} =~ s/\n//g; $sip_in->{barcode} =~ s/\r//g;

   $sip_in->{terminal_password} = getValueByPrefix('AC',$x);
   if ($debug) { print LOGFILE "DEBUG sip_in is:\n".Dumper($sip_in); }
   $sip_out->{service}='18';
   $sip_out->{circulation_status}='';  #two chars, the values are 1-other, 2-an order, 3-available, 4-charged, 5-charged, not be recalled; 6-in process, 7-recalled, 8-waiting on hold shelf, 9 waiting to be reshelved
                                         #                               10 in treansit between library locations, 11 claimed returned, 12 lost, 13 missing
                                         # Note - here currently onlu the 2 statuses are used: 4 - loaned, 3 - not loaned !!!
   $sip_out->{security_marker}='00';  #two chars. The values are 00-other, 01-none, 02-3M Tattle-Tape Security Strip, 03-3M Whisper Tape
   $sip_out->{fee_type}='01';  #two chars
   $sip_out->{datetime} = strftime "%Y%m%d    %H%M%S", localtime;
   $sip_out->{barcode} = 'AB'.$sip_in->{barcode}.'|' ;# prefix AB
   $sip_out->{title} = '';# prefix AJ, 
   $sip_out->{due_date} = '';# prefix AH
   $sip_out->{permament_location} = '';# prefix AQ
   $sip_out->{screen_message} = '';# prefix AF, hlaseni pro uzivate;e
   $sip_out->{print_line} = '';# prefix AG, stejny text jako AF

   if ( $sip_in->{barcode} ) {
      #call api ill-item-by-bc
      my $ibc={};
         $ibc->{'op'} = 'ill-item-by-bc';
         $ibc->{'barcode'} = uri_escape($sip_in->{barcode});
         $ibc->{'library'} = $adm_base;
         $ibc->{'user_name'}=$ill_item_by_bc_user if ($ill_item_by_bc_user);
         $ibc->{'user_password'}=$ill_item_by_bc_pas if ($ill_item_by_bc_pas);
      my $item_info = callXserver($ibc);
      unless ( $item_info ) { 
         $is_error='Response of X-server for request ill-item-by-bc is empty'; 
         $sip_out->{title}="Nelze se pripojit k API Alephu.";
         exceptionError($is_error); 
         }
      if ( not($item_info->{z30}->{'z30-doc-number'}) and not($item_info->{z30}->{'z30-item-sequence'}) )  {
         $is_error='Response of X-server for request ill-item-by-bc does not contain /z30/z30-doc-number element. Item key cannot be determined.';
         $sip_out->{title}="Jednotka s kodem ".$sip_in->{barcode}." nenalezena";
         exceptionError($is_error);
         }
      if ( $is_error ) {
         print LOGFILE "Response message 18 error found - returning circulation status 01\n";
         $sip_out->{'circulation_status'}='01'; 
         }
      else {
         #get title - call API ill-get-doc-short 20220608
         my $gds={};
         $gds->{op}='ill-get-doc-short';
         $gds->{'doc_number'} = sprintf("%09d",$item_info->{z30}->{'z30-doc-number'});
         $gds->{'library'}=$adm_base;
         my $doc_short = callXserver($gds);
         if ( $doc_short ) {  
            if ( $doc_short->{z13}->{'z13-title'} ) { 
               $sip_out->{title} = $doc_short->{z13}->{'z13-title'};
               #$sip_out->{title} = 'Ukradena kniha';
               $sip_out->{title} =~ s/\s*[:\/\.,]$//;
               }
            else {
               print LOGFILE "WARNING - X-Server API ill-get-doc-short - no /z13/z13-title found in response -  Item title cannot be determined.\n";
               $sip_out->{title} = 'Ukradena kniha';
               }
            }
         else {
            print LOGFILE "WARNING - X-Server API ill-get-doc-short returned no or errorneous response -  Item title cannot be determined.\n";
            $sip_out->{title} = $sip_out->{title} ? $sip_out->{title} : 'Ukradena kniha';
            }

         #call API ill-loan-info
         my $lic={};
         $lic->{op}='ill-loan-info';
         $lic->{'doc_number'} = sprintf("%09d",$item_info->{z30}->{'z30-doc-number'});
         $lic->{'item_seq'} = sprintf("%06d",$item_info->{z30}->{'z30-item-sequence'});
         $lic->{'library'}=$adm_base;
         $lic->{'user_name'}=$ill_loan_info_user if ($ill_loan_info_user);
         $lic->{'user_password'}=$ill_loan_info_pas if ($ill_loan_info_pas);
           my $loan_info = callXserver($lic);
           unless ( $loan_info ) { $is_error='Response of X-server for request ill-loan-info is empty'; exceptionError($is_error); }
       
          #gather data for sip response
          #TODO ciruclation_status 08 je on hold shelf, we would need another api call to get information about the hold request
          #11 claimed returned
          #12 lost
          #13 missing
          $sip_out->{circulation_status}='00';#undefined return value
          if ( $item_info->{z30} ) {
            my ($ips)=$item_info->{z30}->{'z30-item-process-status'};
            if ($ips) {
               my @ips_match = grep(/^\Q$ips\E$/, @in_process_status);
               if (scalar @ips_match > 0 ) { $sip_out->{circulation_status}='06'; } #in process
               my @miss_match = grep(/^\Q$ips\E$/, @missing_status);
               if (scalar @miss_match > 0 ) { $sip_out->{circulation_status}='12'; } #lost
               }
            }
          if ( $sip_out->{circulation_status} eq '00' and $loan_info->{'z36'} ) { #reposne has loan record
            if ( $loan_info->{'z36'}->{'z36-bor-status'} eq $transfer_patron ) { #in transit loan
               $sip_out->{circulation_status}='10';}
            else { #loaned
               $sip_out->{circulation_status}='04';
               if ( $loan_info->{'z36'}->{'z36-due-date'} ) {
                  my $dd=$loan_info->{'z36'}->{'z36-due-date'};
                  $sip_out->{due_date} = 'AH'.substr($dd,6,4).substr($dd,3,2).substr($dd,0,2).'|';
                  }
               }
             }
          else { $sip_out->{'circulation_status'}='03'; } #available
          $sip_out->{permament_location} = 'AQ'.$item_info->{'z30'}->{'z30-collection'}.'|' if ( $item_info->{'z30'}->{'z30-collection'} ) ;
          $sip_out->{title} = 'AJ'.$sip_out->{title}.'|' if $sip_out->{title};
       }
       #construct and return SIP response
       $sip_out->{datetime} = strftime "%Y%m%d    %H%M%S", localtime;

       if ( $sip_out->{'circulation_status'} eq '01') {#chyba 
          return $sip_out->{service} . $sip_out->{circulation_status} . $sip_out->{security_marker} . $sip_out->{fee_type} . $sip_out->{datetime} . $sip_out->{barcode} ; }
       else {
          return $sip_out->{service} . $sip_out->{circulation_status} . $sip_out->{security_marker} . $sip_out->{fee_type} . $sip_out->{datetime} . $sip_out->{due_date} . $sip_out->{barcode} . $sip_out->{title} . $sip_out->{permament_location} . $sip_out->{screen_message} . $sip_out->{print_line} . "\r";}
       
      }
   else { $is_error="Barcode not found in SIP2 request: $x"; exceptionError($is_error); }
   }
#sub itemInformation END



#sub for ASC libary system login
#NOTE!  No login is currently in use. The response will be always OK, regardeless the login info
sub ACSlogin {
   my ($x)=@_;
   $sip_in->{service}='93';
   $sip_out->{service}='94'; #2 chars
   $sip_out->{'ok'}='1'; #1 char 0/1
   return $sip_out->{service} . $sip_out->{'ok'} . "\r";
   }


#sub for ASC libary system status
#   input structure is: 99
#       status code - 1 char: 0 or 1 or 2  (what does it mean?)
#       max print width = 3 chars
#       protocol version - 4 chars with structure x.xx
#   output structure is: 98
#       for further values see hashref $sip_out below

 
sub ACSstatus {
   print LOGFILE "processing 99 - ACSstatus\n";
   my ($x)=@_;
   $sip_in->{service}='99';
   $sip_out->{service}='98'; #2 chars
   $sip_out->{'online-status'}='Y'; #1 char Y/N
   $sip_out->{'checkin-ok'}='N'; #1 char Y/N
   $sip_out->{'checkout-ok'}='N'; #1 char Y/N
   $sip_out->{'acs-renewal-policy'}='N'; #1 char Y/N
   $sip_out->{'status-update-ok'}='N'; #1 char Y/N
   $sip_out->{'offline-ok'}='Y'; #1 char Y/N
   $sip_out->{'timeout-period'}='999'; #3 chars
   $sip_out->{'retries-allowed'}='000'; #3 chars
   $sip_out->{datetime} = strftime "%Y%m%d    %H%M%S", localtime; #18 chars
   $sip_out->{'protocol-version'} = '2.00'; #4 chars x.xx
   $sip_out->{'AO'} = ''; #Institution ID (leave empty if not used), variable length
   $sip_out->{'BX'} = 'NNNNYNNNNNYNNNNN'; #Information for SC, which messages are currently supported by ASC
                                          #for currentl available messages 17/18 (item info), position 10 (starting from zero) has been changed to Y
                                          #    and position 4 also to Y  (SC/ASC status]
                                          #When other services will be added to this script, they should be also added to this response

   return $sip_out->{service} . $sip_out->{'online-status'} . $sip_out->{'checkin-ok'} . $sip_out->{'checkout-ok'} . $sip_out->{'acs-renewal-policy'} . $sip_out->{'status-update-ok'} . $sip_out->{'offline-ok'} . $sip_out->{'timeout-period'} . $sip_out->{'retries-allowed'} . $sip_out->{datetime} . $sip_out->{'protocol-version'} . 'AO' . $sip_out->{'AO'} . '|BX' . $sip_out->{'BX'} . "|\r";

   }




#sub for extracting arguments from string using prefix (for SIP2 in requests)
#  arguments:  prefix (like 'AO', 'AN' etc.)
#              string of the request
# returns the value of the argument with the prefix or zero length string if not found
sub getValueByPrefix {
   my ($sprefix,$stext)=@_;
   my ($srettext) = $stext =~ /(\Q$sprefix\E[^|]*)/;
   return '' unless ($srettext);
   $srettext =~ s/^$sprefix//;
   return $srettext;
   }


#sub for callint Aleph X-server API
#  argument - hashref wirh keys as url arguments an values and their values
#  returns hashref to which xml response have been converted to. Mind the ForceArray=>0 settings here - only first value of nodes is returned as a string
sub callXserver {
   my ($x)= shift;
   my $sresponse={};
   my $url_path=$xserver_url;
   my $loop=0;
   foreach my $key (keys %$x) {
     if ($loop==0) { $url_path .= '?';}
     else { $url_path .= '&' }
     $url_path .= $key.'='.$x->{$key};
     $loop++;
     }
   print LOGFILE "      calling api $url_path\n";
   my $sr = LWP::UserAgent->new;
   my $sr2 = $sr->get( $url_path);
   if ( $sr2->is_success ) {
     $sresponse=XMLin( $sr2->content, SuppressEmpty => 1, ForceArray => 0 );
     print LOGFILE "DEBUG xserver response: ".Dumper($sresponse) if ($debug);
     if ( $sresponse->{'error'} ) { unless ( $sresponse->{'error'} eq 'OK' or $sresponse->{'error'} eq 'O.K.' or $sresponse->{'error'} eq 'Loan record could not be found') {
        exceptionError ('x-server call '.$xserver_url.' returns error: '.$sresponse->{'error'} );
        } }
     return $sresponse;
     }
   else { exceptionError ('x-server call '.$xserver_url.' does not respond' ); }
   return $sresponse;
   }

#sub for counting checksum accroding to SIP definition
#  made by solution here https://stackify.dev/521156-sip2-checksum-calculation-in-javascript 
#   parameter: ACS response
#   returns: counted checksum
#   WARNING!  Not completed yet, returned checksum is not correct, do not use checksum for SIP requests :-!
sub countChecksum {
   my ($m)=@_;
   my $checksum_int = 0;
   my $checksum_binary_string = "";
   my $checksum_binary_string_inverted = "";
   my $checksum_binary_string_inverted_plus1 = "";
   my $checksum_hex_string = "";
   # add each character as an unsigned binary number (loop the string]
   while ($m =~ /(.)/sg) { $checksum_int += ord($1);} 
   # convert integer to binary representation stored in a string
   while($checksum_int > 0){
      $checksum_binary_string = "($checksum_int % 2)" . $checksum_binary_string;
      $checksum_int = floor($checksum_int / 2);
      }
   # pad binary string to 16 bytes
   while(length($checksum_binary_string) < 16){
      $checksum_binary_string = "0" . $checksum_binary_string;
      }
   # invert the binary string (loop the string)
   while ($checksum_binary_string.length =~ /(.)/sg) {
      my $ch=$1;
      my $inverted_value = "X"; # something weird to make mistakes jump out
      if( $ch eq "1") { $inverted_value = "0"; }
      else { $inverted_value = "1"; }
      $checksum_binary_string_inverted .= $inverted_value;
      }
    # add 1 to the binary string
    my $carry_bit=1;
    my $i=length($checksum_binary_string_inverted);
    while ($i>-1) {
       if($carry_bit){
          if( substr($checksum_binary_string_inverted,$i,1) eq "0") {
             $checksum_binary_string_inverted_plus1 = "1" + $checksum_binary_string_inverted_plus1;
             $carry_bit = 0;
             } 
          else {
             $checksum_binary_string_inverted_plus1 = "0" + $checksum_binary_string_inverted_plus1;
             $carry_bit = 1;
             }
          } 
       else {
          $checksum_binary_string_inverted_plus1 = substr($checksum_binary_string_inverted,$i,1) . $checksum_binary_string_inverted_plus1;
          }
       $i--;
       }
    # convert binary string to hex string and uppercase it because that's what the gateway likes
    $checksum_hex_string = uc ( sprintf("0x%X", ($checksum_binary_string_inverted_plus1+0)));
    return $checksum_hex_string;
   }


#sub for handling fatal errora:
#   does not stop script processing, writes log, sends mail alert  nad returns SIP response as error #TODO
#   argument: error message 9stirng0
sub exceptionError {
   my ($error_text)=@_;
   $now=strftime "%Y%m%d-%H:%M:%S", localtime;
   print LOGFILE "Error - $now : $error_text (SIP request cannot be processed)\n\n";
   print  "Error - $now : $error_text (SIP request cannot be processed)\n\n"; #DEBUG
   open(MAIL, "|/usr/sbin/sendmail -t");
   print MAIL "To: ".$admin_mail."\n";
   print MAIL 'From: aleph@alois.osu.cz'."\n";
   print MAIL 'Subject: sip2mini.pl (SIP2 server) error'."\n\n";
   print MAIL "$error_text\n";
   print MAIL "$now\n";
   close(MAIL);
   #return 1;
   }

`        
