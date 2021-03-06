#!/bin/bash
args=("$@")

function die(){
	exit 0;
}

function yes_or_not(){
	case "$1" in 
	y|Y ) return 0;;
	* ) return 1;;
	esac
}


NC='\033[0m' # No Color
function echo_e(){
	case $1 in 
		red)	echo -e "\033[0;31m$2 ${NC} " ;;
		green) 	echo -e "\033[0;32m$2 ${NC} " ;;
		yellow) echo -e "\033[0;33m$2 ${NC} " ;;
		blue)	echo -e "\033[0;34m$2 ${NC} " ;;
		purple)	echo -e "\033[0;35m$2 ${NC} " ;;
		cyan) 	echo -e "\033[0;36m$2 ${NC} " ;;
		*) echo $1;;
	esac
}

function is_installed(){
	PACKAGE=$1

	dpkg -s $1 &> /dev/null

	if [ ! $? -eq 0 ]; then
		echo_e red "[-] $PACKAGE  not installed..."
		apt-get install -y $PACKAGE
		echo_e green "[+]  $PACKAGE  is installed"
	fi

}

function remove_all(){
  echo -ne "[+] Are you sure? (y/n): "
	read OPTION
	if yes_or_not $OPTION
	then
              apt-get purge postfix --autoremove -y
              apt-get purge dovecot-core dovecot-imapd --autoremove -y 
	fi
	die 
}     

function is_root(){

if [ $(id -u) = 0 ]
then
	#CHECK PACKAGE 
       is_installed postfix
       is_installed dovecot-core 
       is_installed dovecot-imapd
       is_installed opendkim
       is_installed opendkim-tools

else
	echo "You must be root to acces"
	exit 1
fi 
}

function install(){

is_configured=$(cat /etc/postfix/main.cf | grep "non_smtpd_milters = inet:localhost:12301")


if [[ $is_configured = "" ]]
then

#ADD FIRST USER EX: admin --> admin@"yourdomain"
       USER=${args[1]}
       if [ ! $USER ]
              then
              echo_e red "[-] You must enter init user"
              die
              
       fi

#ADD FQDN 
       DOMAIN=${args[2]}
       if [ ! $DOMAIN ]
              then
              echo_e red "[-] You must enter DOMAIN "
              echo_e yellow "[?] To configure you can user toolnet https://github.com/nrikeDevelop/toolnet "
              die
       fi

#CREATE CERTIFICATE

       if [ ! -d /etc/letsencrypt/live/$DOMAIN ]
       then

              echo_e "[?] If there is an error with the certificate, check the server"
              certbot certonly --standalone --preferred-challenges http -d $DOMAIN
              echo ""
              echo -ne "[+] correctly? (y/n): "
              read OPTION
              if  ! yes_or_not $OPTION
              then
                     echo_e yellow "[?] check the server, services listen port 80"
                     die
              fi

       else
              echo_e green "[+] Certificate already exist"
       fi



#CREATE USER 
       adduser $USER

#POSTFIX
#https://upcloud.com/community/tutorials/secure-postfix-using-lets-encrypt/

echo_e yellow "use root "
sleep 1       
sudo dpkg-reconfigure postfix


sudo postconf -e 'home_mailbox = Maildir/'
sudo postconf -e "mydomain = $DOMAIN"
sudo postconf -e "smtpd_tls_cert_file = /etc/letsencrypt/live/$DOMAIN/fullchain.pem"
sudo postconf -e "smtpd_tls_key_file = /etc/letsencrypt/live/$DOMAIN/privkey.pem"
sudo postconf -e 'smtpd_sasl_type = dovecot'
sudo postconf -e 'smtpd_sasl_path = private/auth'
sudo postconf -e 'smtpd_sasl_local_domain ='
sudo postconf -e 'smtpd_sasl_security_options = noanonymous'
sudo postconf -e 'broken_sasl_auth_clients = yes'
sudo postconf -e 'smtpd_sasl_auth_enable = yes'
sudo postconf -e 'smtpd_recipient_restrictions = permit_sasl_authenticated,permit_mynetworks,reject_unauth_destination'
sudo postconf -e 'smtp_tls_security_level = may'
sudo postconf -e 'smtpd_tls_security_level = may'
sudo postconf -e 'smtp_tls_note_starttls_offer = yes'
sudo postconf -e 'smtpd_tls_loglevel = 1'
sudo postconf -e 'smtpd_tls_received_header = yes'

#DOVECOT
#https://www.hackster.io/gulyasal/make-a-mail-server-out-of-your-rpi3-5829f0

sudo maildirmake.dovecot /etc/skel/Maildir
sudo maildirmake.dovecot /etc/skel/Maildir/.Drafts
sudo maildirmake.dovecot /etc/skel/Maildir/.Sent
sudo maildirmake.dovecot /etc/skel/Maildir/.Spam
sudo maildirmake.dovecot /etc/skel/Maildir/.Trash
sudo maildirmake.dovecot /etc/skel/Maildir/.Templates
sudo maildirmake.dovecot /etc/skel/Maildir/.Junk

sudo chown -R $USER:$USER /home/$USER/Maildir
sudo chmod -R 700 /home/$USER/Maildir

echo "$DOMAIN         REJECT          Email rejected - cannot verify identity" >/etc/postfix/helo_access

postmap /etc/postfix/helo_access

echo '
!include_try /usr/share/dovecot/protocols.d/*.protocol
listen = *
dict {
       #configurations suppressed
}
!include conf.d/*.conf
!include_try local.conf
'>/etc/dovecot/dovecot.conf

echo_e yellow "[?] >/etc/dovecot/dovecot.conf has been configured"

mv /etc/dovecot/conf.d/10-mail.conf /etc/dovecot/conf.d/10-mail.conf.back
rm -rf /etc/dovecot/conf.d/10-mail.conf

echo '
mail_location = maildir:~/Maildir
namespace inbox {
    inbox = yes
}
mail_privileged_group = mail
protocol !indexer-worker { 
       #configure supressed
}
' >/etc/dovecot/conf.d/10-mail.conf

echo_e yellow "[?] >/etc/dovecot/conf.d/10-mail.conf has been configured"


echo '
service imap-login {
 inet_listener imap {
   port = 143
 }
 inet_listener imaps {
   port = 993
   ssl = yes
 }
}
service auth {
       unix_listener /var/spool/postfix/private/auth {
               mode = 0660
               user = postfix
               group = postfix
       }
}
'>/etc/dovecot/conf.d/10-master.conf

echo_e yellow "[?] >/etc/dovecot/conf.d/10-master.conf has been configured"



echo '
disable_plaintext_auth = no
auth_mechanisms = plain login
!include auth-system.conf.ext
'>/etc/dovecot/conf.d/10-auth.conf

echo_e yellow "[?] >/etc/dovecot/conf.d/10-auth.conf has been configured"



echo '
ssl = yes
ssl_protocols = !SSLv3
ssl_cert = </etc/letsencrypt/live/'$DOMAIN'/fullchain.pem 
ssl_key = </etc/letsencrypt/live/'$DOMAIN'/privkey.pem 
'>/etc/dovecot/conf.d/10-ssl.conf

echo_e yellow "[?] >/etc/dovecot/conf.d/10-ssl.conf"


echo '
smtps     inet  n       -       -       -       -       smtpd
 -o syslog_name=postfix/smtps
 -o smtpd_tls_wrappermode=yes
 -o smtpd_recipient_restrictions=permit_sasl_authenticated,reject
spamassassin    unix  -       n       n       -       -       pipe user=debian-spamd argv=/usr/bin/spamc -f -e /usr/sbin/sendmail -oi -f ${sender} ${recipient}
'>>/etc/postfix/master.cf

echo_e yellow "[?] >/etc/postfix/master.cf"

service postfix restart
service dovecot restart

#TODO : CONFIGURATION CORRECT

#DKIM
#https://www.hackster.io/gulyasal/make-a-mail-server-out-of-your-rpi3-5829f0

echo ' 
AutoRestart             Yes
AutoRestartRate         10/1h
SyslogSuccess           Yes
LogWhy                  Yes
Canonicalization        relaxed/simple
ExternalIgnoreList      refile:/etc/opendkim/TrustedHosts
InternalHosts           refile:/etc/opendkim/TrustedHosts
KeyTable                refile:/etc/opendkim/KeyTable
SigningTable            refile:/etc/opendkim/SigningTable
Mode                    sv
PidFile                 /var/run/opendkim/opendkim.pid
SignatureAlgorithm      rsa-sha256
UserID                  opendkim:opendkim
Socket                  inet:12301@localhost
'>/etc/opendkim.conf

#if abstract check
echo '

# Command-line options specified here will override the contents of
# /etc/opendkim.conf. See opendkim(8) for a complete list of options.
#DAEMON_OPTS=""
# Change to /var/spool/postfix/var/run/opendkim to use a Unix socket with
# postfix in a chroot:
#RUNDIR=/var/spool/postfix/var/run/opendkim
RUNDIR=/var/run/opendkim
#
# Uncomment to specify an alternate socket
# Note that setting this will override any Socket value in opendkim.conf
# default:
SOCKET=local:$RUNDIR/opendkim.sock
# listen on all interfaces on port 54321:
#SOCKET=inet:54321
# listen on loopback on port 12345:

#TODO: THIS UNCOMENT
SOCKET=inet:12345@localhost

# listen on 192.0.2.1 on port 12345:
#SOCKET=inet:12345@192.0.2.1
USER=opendkim
GROUP=opendkim
PIDFILE=$RUNDIR/$NAME.pid
EXTRAAFTER=
'>>/etc/default/opendkim

sudo mkdir /etc/opendkim
sudo mkdir /etc/opendkim/keys

#INSTALLED AUTO
#echo '
#127.0.0.1
#localhost
#192.168.0.1/24
#'$DOMAIN'
#'>/etc/opendkim/TrustedHosts

#echo 'mail._domainkey.example.com example.com:mail:/etc/opendkim/keys/example.com/mail.private'>/etc/opendkim/KeyTable

#echo '*@example.com mail._domainkey.example.com'>/etc/opendkim/SigningTable

mkdir /etc/opendkim/keys/$DOMAIN
cd /etc/opendkim/keys/$DOMAIN
opendkim-genkey -s mail -d $DOMAIN
chown opendkim:opendkim mail.private
chmod 777 mail.txt
$KEY=$(cat mail.txt)

echo_e yellow "Introduce your FQDN"
read FQDN

echo $KEY >> /etc/bind/$FQDN/db.external.conf

sudo service dovecot reload
sudo service dovecot restart
sudo service postfix reload
sudo service postfix restart
sudo service opendkim restart

echo_e green "TRY IT"

die

fi
}

function install_toolmail(){
       if [ -f "/usr/sbin/toolmail" ]
	then 
		rm -r /usr/sbin/toolmail
		cp ./bind_generator.sh /usr/sbin/toolmail
	else
		cp ./bind_generator.sh /usr/sbin/toolmail
	fi	
	echo_e green "[+] toolmail installed in /usr/sbin like toolmail "

}

function helper(){
echo '
toolmail 
	[COMMON OPTION]
       --install            [user_name]   [domain]
       --install-toolmail
       --add-user		[user_name]
       --help|-h
       --additional-help
'	
	die 
}

function additional_helper(){
echo ""
echo "Use toolnet to configure bind"
echo "Your dns must be like :"
echo ""
echo '
$ORIGIN <DOMAIN>
$TTL	86400
@	IN	SOA	ns1. root.localhost. (
1		; Serial
604800		; Refresh
86400		; Retry
2419200		; Expire
86400 )	; Negative Cache TTL
;
@	IN	NS	ns1
@	IN	PTR	mail
@	IN	MX	10 mail
ns1	IN	A	<IP>
mail	IN	A	<IP>
'
echo ""
die
}

function init_menu(){
	case ${args[0]} in
              "--install_toolmail")
                     install_toolmail
                     die ;;
              "--install")
                     install
                     die ;;
              "--remove-all")
                     remove_all
                     die;;
              "--additional-help")
			additional_helper 
                     die ;;
		"--help"|"-h")
			helper 
                     die ;;
		*)
		helper 
		die ;;

	esac
}
#MAIN
is_root

init_menu