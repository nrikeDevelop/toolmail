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
       is_installed dovecot-core dovecot-imapd
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

#CREATE USER 
       adduser $USER

echo '
# See /usr/share/postfix/main.cf.dist for a commented, more complete version


# Debian specific:  Specifying a file name will cause the first
# line of that file to be used as the name.  The Debian default
# is /etc/mailname.
#myorigin = /etc/mailname

smtpd_banner = $myhostname ESMTP $mail_name (Raspbian)
biff = no

append_dot_mydomain = no

# Uncomment the next line to generate "delayed mail" warnings
#delay_warning_time = 4h

readme_directory = no

# See http://www.postfix.org/COMPATIBILITY_README.html -- default to 2 on
# fresh installs.
compatibility_level = 2

# TLS parameters
smtpd_tls_cert_file = /etc/letsencrypt/live/mail.raspylab.cf/fullchain.pem
smtpd_tls_key_file = /etc/letsencrypt/live/mail.raspylab.cf/privkey.pem
smtpd_use_tls=yes
smtpd_tls_session_cache_database = btree:${data_directory}/smtpd_scache
smtp_tls_session_cache_database = btree:${data_directory}/smtp_scache

# See /usr/share/doc/postfix/TLS_README.gz in the postfix-doc package for
# information on enabling SSL in the smtp client.

smtpd_relay_restrictions = permit_mynetworks permit_sasl_authenticated defer_unauth_destination
myhostname = '$DOMAIN'
alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases
myorigin = /etc/mailname
mydestination = $myhostname, mail.raspylab.cf, raspylab.cf, localhost.cf, localhost
relayhost =
mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128
mailbox_size_limit = 0
recipient_delimiter = +
inet_interfaces = all
inet_protocols = all

home_mailbox = Maildir/
mailbox_command =
smtpd_recipient_restrictions =
       permit_sasl_authenticated,
       permit_mynetworks,
       reject_unauth_destination
smtpd_helo_required = yes
smtpd_helo_restrictions =
       permit_mynetworks,
       permit_sasl_authenticated,
       reject_invalid_helo_hostname,
       reject_non_fqdn_helo_hostname,
       reject_unknown_helo_hostname,
       check_helo_access hash:/etc/postfix/helo_access
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
smtpd_sasl_auth_enable = yes
smtpd_tls_auth_only = yes
milter_protocol = 2
milter_default_action = accept
smtpd_milters = inet:localhost:12301
non_smtpd_milters = inet:localhost:12301
'> /etc/postfix/main.cf

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


echo '
!include_try /usr/share/dovecot/protocols.d/*.protocol
listen = *
dict { }
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
protocol !indexer-worker { }
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
'	
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