#!/bin/bash

function run {

if [[ ! -f ./bin/mongod ]]; then
echo "server bin download start"
if [[ -d tmp ]]; then
rm -rf tmp
fi
mkdir tmp
cd tmp
install_ver=""
dl_page_verln=$(
wget -q -O - https://www.mongodb.com/try/download/community | 
	grep -F 'window.__serverData=' )
dl_page_ver_t1=${dl_page_verln/"window.__serverData="}
dl_page_ver_json=$(echo -n ${dl_page_ver_t1/"</script>"} | 
	jq -r .components[2].props.embeddedComponents[0].props.items[2].embeddedComponents[0].props.data[0].data[0] )
echo ${dl_page_ver_json} > a.json
install_ver=$(echo ${dl_page_ver_json} | jq keys[] | while read -r ln; do
cur_ver=$(echo ${ln} | jq -r )
is_stable=$(echo ${dl_page_ver_json} | 
	jq -r ".\"${cur_ver}\".meta.current" )
if [[ "true" == ${is_stable} ]]; then
echo ${cur_ver}
fi
done )
if [[ 1 -ne $(echo "${install_ver}" | wc -l ) ]]; then
echo "invalid stable version"
echo ${install_ver}
exit 1
fi
install_system=$(lsb_release -is)
install_arch=""
case $(uname -m) in
	x86_64 | amd64)
		install_arch="amd" 
		;;
	arm64 | arm64-v8a)
		install_arch="arm"
		;;
	arm)
		dpkg --print-architecture | grep -q "arm64" && install_arch="arm"
		;;
esac
case ${install_arch} in
	amd)
		install_arch='x64'
		;;
	arm)
		install_arch='ARM 64'
		;;
	*)
		echo "invalid architecture"
		exit 1
		;;
esac

install_platform=$(echo ${dl_page_ver_json} | 
	jq -r .\"${install_ver}\".sortedPlatforms[] | 
while read -r ln; do
	if [[ -z $(echo ${ln} | grep -iF ${install_arch} ) ]] ||
		[[ -z $(echo ${ln} | grep -iF ${install_system} ) ]]; then
		continue
	fi
	echo ${ln}
done )
if [[ 1 -lt $(echo "${install_platform}" | wc -l ) ]]; then
install_system_ver=$(lsb_release -sr )
install_platform=$(echo "${install_platform}" | while read -r ln; do
if [[ -z $(echo ${ln} | grep -iF ${install_system_ver} ) ]]; then
	continue
fi
echo ${ln}
done )
fi
if [[ 1 -ne $(echo "${install_platform}" | wc -l ) ]]; then
	echo "invalid platform"
	echo ${install_platform}
	exit 1
fi
install_link=$(echo ${dl_page_ver_json} | 
	jq -r ".\"${install_ver}\".platforms.\"${install_platform}\".tgz" )
echo "download:" ${install_link}
wget "${install_link}"
7zz x *.tgz
7zz x *.tar
rm *.tgz *.tar
cd ..
rm -rf bin
mv ./tmp/*/bin ./bin
rm -rf tmp
chmod +x ./bin/*
echo "server bin download end"
fi

if [[ -d run ]]; then
	rm -rf run
fi
mkdir run
touch run/log

#if [[ ! -d hvlog ]]; then
#	mkdir hvlog
#fi

if [[ -d tz ]]; then
	rm -rf tz
fi

rm conf/main.conf
v2=$(pwd|sed 's/\//\\\//g')
cat conf/main.t.conf | sed "s/\${PWD}/${v2}/g" > conf/main.conf

rm -rf tzd
mkdir tzd
cd tzd
wget https://downloads.mongodb.org/olson_tz_db/timezonedb-latest.zip
7zz x timezonedb-latest.zip
rm timezonedb-latest.zip
for v1 in *; do
	if [[ -d ${v1} ]]; then
		mv $v1 ../tz
		break
	fi
done
cd ..
rm -rf tzd

ulimit -Hn 1048576
ulimit -Sn 65536

if [[ ! -d data ]]; then
	mkdir data
fi
echo "start run"
./bin/mongod -f ./conf/main.conf
echo "end run"

}

function main {
while true; do
run
sleep 15
done

}

main

