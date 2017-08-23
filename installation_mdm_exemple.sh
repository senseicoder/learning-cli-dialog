#!/bin/bash

log=/var/log/epiconcept_install.log

function droitsroot()
{
	if [ "$LOGNAME" != 'root' ]; then
		echo "exécuter à nouveau avec sudo (droits root nécessaires)"
		exit 1
	fi
}

droitsroot

echo "installation des logiciels, veuillez patientez cela peut prendre quelques minutes"
echo "le log d'installation est dans $log dorénavant"

version=$(cat /etc/apt/sources.list | grep "^deb " | awk '{print $3}' | sed -e 's#[/-].*##' | uniq)
echo "deb https://files.epiconcept.fr/repositories_apt/epiconcept $version main" > /etc/apt/sources.list.d/epiconcept.list

export DEBIAN_FRONTEND=noninteractive

echo 'console-data    console-data/keymap/family      select  azerty' | debconf-set-selections
echo 'console-data    console-data/keymap/azerty/french/variant       select  PC keyboard (non-US 102 keys)' | debconf-set-selections

echo 'console-common  console-data/keymap/template/layout     select' | debconf-set-selections
echo 'console-common  console-data/keymap/full        select  fr-latin9' | debconf-set-selections
echo 'console-common  console-data/keymap/template/variant    select' | debconf-set-selections
echo 'console-common  console-data/keymap/family      select  azerty' | debconf-set-selections
echo 'console-common  console-data/bootmap-md5sum     string  a27842ee95c885d54a86c2ceac224cde' | debconf-set-selections
echo 'console-common  console-data/keymap/policy      select  Select keymap from full list' | debconf-set-selections
echo 'console-common  console-data/keymap/template/keymap     select' | debconf-set-selections
echo 'console-common  console-data/keymap/powerpcadb  boolean' | debconf-set-selections
echo 'console-common  console-data/keymap/ignored     note' | debconf-set-selections

echo 'postfix postfix/procmail        boolean' | debconf-set-selections
echo 'postfix postfix/rfc1035_violation       boolean false' | debconf-set-selections
echo 'postfix postfix/retry_upgrade_warning   boolean' | debconf-set-selections
echo 'postfix postfix/relay_restrictions_warning      boolean' | debconf-set-selections
echo 'postfix postfix/relayhost       string' | debconf-set-selections
echo 'postfix postfix/destinations    string' | debconf-set-selections
echo 'postfix postfix/tlsmgr_upgrade_warning  boolean' | debconf-set-selections
echo 'postfix postfix/mydomain_warning        boolean' | debconf-set-selections
echo 'postfix postfix/kernel_version_warning  boolean' | debconf-set-selections
echo 'postfix postfix/protocols       select' | debconf-set-selections
echo 'postfix postfix/mailname        string  /etc/mailname' | debconf-set-selections
echo 'postfix postfix/sqlite_warning  boolean' | debconf-set-selections
echo 'postfix postfix/mynetworks      string  127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128' | debconf-set-selections
echo 'postfix postfix/root_address    string' | debconf-set-selections
echo 'postfix postfix/main_mailer_type        select  No configuration' | debconf-set-selections
echo 'postfix postfix/mailbox_limit   string  0' | debconf-set-selections
echo 'postfix postfix/recipient_delim string  +' | debconf-set-selections
echo 'postfix postfix/chattr  boolean false' | debconf-set-selections

echo "lancement" > $log
apt-get update --quiet >> $log 2>&1
apt-get upgrade -y --force-yes --quiet >> $log 2>&1
apt-get install --yes --force-yes --quiet openssh-server mysql-server >> $log 2>&1

echo "Restriction des droits"
chmod 600 -f /etc/mysql/conf.d/client.cnf
chmod 600 /opt/mdmdpi/conf.inc.php
chmod 600 /opt/mdmdpi/conf.inc.php.specifique
chmod 600 /opt/mdmdpi/decrypt.sh
chmod 600 /opt/mdmdpi/make_keys.sh
chmod 600 /opt/mdmdpi/mdmdpi_public.key
chmod 600 /opt/mdmdpi/ws.ini

deluser mdm sudo

passwd root

mysql -uroot -proot -e 'select * from mysql.user' > /dev/null
if [ $? -ne 0 ]; then
	echo "correction accès mysql" >> $log 2>&1
	/usr/bin/mysqladmin -u root --password="" password 'root' >> $log 2>&1

	mysql -uroot -proot -e 'select * from mysql.user' > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		echo "erreur à la configuration de Mysql, arrêt de l'installation"
		exit 1
	fi
fi

echo "installation logiciels MDMDPI"
apt-get install --yes --force-yes --quiet openssh-server epi-mdm mdmdpi >> $log 2>&1

url=$(awk -F "=" '/url/ {print $2}' /opt/mdmdpi/ws.ini)
urlsurveys=$(echo $url | sed -e "s/index/surveys/g")
urlgroups=$(echo $url | sed -e "s/index/groups/g")

wget --quiet --output-document=surveys.csv ${urlsurveys}
input=surveys.csv
OPTIONS=()
IDS=(0)
COUNT=0

while IFS=: read -r id label
do
    COUNT=$[COUNT+1]
    OPTIONS+=($COUNT "$label")
    IDS+=("$id")
done < "$input"

cmd=(dialog --clear --menu "Choisir une enquête" 15 45 5)
choices=$("${cmd[@]}" "${OPTIONS[@]}" 2>&1 >/dev/tty)
for choice in $choices
do
   enquete=${IDS[$choice]}
done

rm $input

if [ -z "$enquete" ]; then
	echo "enquete vide"
	exit 1
fi

wget --quiet --output-document=groups.csv ${urlgroups}?survey=${enquete}
input=groups.csv
OPTIONS=()
IDS=(0)
COUNT=0

while IFS=: read -r id label
do
    COUNT=$[COUNT+1]
    OPTIONS+=($COUNT "$label")
    IDS+=("$id")
done < "$input"

cmd=(dialog --clear --menu "Choisir un groupe" 15 45 5)
choices=$("${cmd[@]}" "${OPTIONS[@]}" 2>&1 >/dev/tty)
for choice in $choices
do
  id_groupe=${IDS[$choice]}
done

rm $input

if [ -z "$id_groupe" ]; then
	echo "groupe vide"
	exit 1
fi

nom=$(uname -n)
if [ -z "$nom" ]; then
	echo "nom vide"
	exit 1
fi

o=/opt/mdmdpi/conf.inc.php
f=$o.specifique
cp $o $f
sed -i $f -e "s/%%BASE_GROUP%%/$id_groupe/g"
sed -i $f -e "s/%%NETBOOK_NAME%%/$nom/g"
sed -i $f -e "s/%%ID_ENQUETE%%/$enquete/g"

mod=700
apacheUser=www-data

mkdir -p /space/applistmp/vrac/tmp/
chown -R $apacheUser /space/applistmp/
chmod -R $mod /space/applistmp

echo "synchronisation de la base de données et des fichiers - cela peut prendre longtemps, ne pas interrompre"
urlbase=$(echo $url | sed -e "s/index/base/g")
wget --quiet --output-document=base.sql ${urlbase}
mysql -e "CREATE SCHEMA IF NOT EXISTS mdmdpi" --batch --silent
mysql mdmdpi < base.sql
rm base.sql

reconfiguration.sh >> $log 2>&1

for i in $(mysql mdmdpi -e "SELECT directory FROM sb_enquete WHERE id_enquete=$enquete" --batch --silent); do
  directory=$(echo $i)
done

#droits pour les données
dir=/space/applisdata/mdmdpi/${directory}
mkdir -p $dir
liste=$(mysql --batch -e "select id from mdmdpi.sb_queges where id_enquete=$enquete and name like 'upload%'" | grep -v ^id)
for i in $liste; do mkdir -p $dir/files_$i; done
chown -R $apacheUser /space/applisdata/mdmdpi
chmod -R $mod /space/applisdata

chown -R $apacheUser /space/www/apps/mdmdpi
chmod -R $mod /space/www/apps/mdmdpi

ecrecupdata.sh >> $log 2>&1

f=/home/mdm/Desktop/Enquete.desktop
sed -i $f -e "s#http://127.0.0.1/enquetes/.*/scripts/#http://127.0.0.1/enquetes/${directory}/scripts/#"

cp /home/mdm/Desktop/* /home/mdm/Bureau/
chown -R mdm:mdm /home/mdm/

touch /etc/cron.d/mdmdpi
chown root:root /usr/local/bin/ecmaj
chmod 4755 /usr/local/bin/ecmaj

echo "fin de l'installation"
