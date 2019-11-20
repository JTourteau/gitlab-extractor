#!/bin/bash

AUTH=
BROWSE=false
ID=
KEY=
OUTPUT=
URL=https://gitlab.com
NO_PROXY=false
CSV_FILE=
BROWSE_FILE=
PARAMS="?per_page=100&page=1"
DESCRIPTION="Retrieve gitlab project's content as JSON file. \n \
             	The content is either stored in a file or printed on standard output. \n \
             	The JSON content can also be oppened into a web browser.
             	\n \
             	NOTE : 'curl' package has to be installed."
GITLAB_API=api/v4/projects
USAGE="Usage: ${0} --id PROJECT_ID [-h|--help] [-a|--auth KEY] [-b|--browse] [-o|--output OUTPUT.json] [-u|--url URL] [--no-proxy] [--export-csv CSV_FILE.csv]\n \
\t\t-h|--help                       : Print this help.\n \
\t\t-a|--auth                       : Authentication key \n \
\t\t-b|--browse                     : Open JSON content with default web browser. \n \
\t\t-i|--id                         : Gitlab project id. \n \
\t\t-o|--output                     : Save JSON content into given file. \n \
\t\t-u|--url                        : Gitlab server URL ('${URL}' as default value).\n \
\t\t--no-proxy                      : Don't use proxies, even if the appropriate *_proxy environment variable is defined.\n \
\t\t--export-csv                    : Convert JSON to CSV file which includes main fields.\n \
\n"

DEPENDENCIES="curl jq"

fail()
{
	echo "ERROR: $*" >&2
	exit 1
}

step()
{
	len=$(echo "$*" | awk '{print length}')
	echo
	seq -s'#' 0 ${len} | tr -d '[:digit:]'
	echo "$*"
	seq -s'#' 0 ${len} | tr -d '[:digit:]'
}

#######################
### Check arguments ###
#######################
[ ${#} -gt 0 ] || { printf "${USAGE}"; exit 1; }

while [ ${#} -ne 0 ]; do
	case "${1}" in
		-h|--help)                  printf "%b\n%b\n" "${USAGE}" "${DESCRIPTION}"; exit 0;;
		-a|--auth)                  shift; KEY=${1};;
		-b|--browse)                BROWSE=true;;
		-i|--id)                    shift; ID=${1};;
		-o|--output)                shift; OUTPUT=${1};;
		-u|--url)                   shift; URL=${1};;
		--no-proxy)                 NO_PROXY=true;;
		--export-csv)               shift; CSV_FILE=${1};;
		*)                          printf "${USAGE}"; exit 1;;
	esac
	shift
done

[ -z "${ID}" ] && fail "You shall specify gitlab project id."
[ -z "${KEY}" ] || AUTH="?private_token=${KEY}"

${NO_PROXY} && { echo "Proxies are disabled"; unset {http,https,HTTP,HTTPS}_{proxy,PROXY}; }

##########################
### Check dependencies ###
##########################
step "### Check dependencies ###"
dpkg -s ${DEPENDENCIES} > /dev/null 2>&1 ||
{
	echo "Missing following packages :"
	echo -n "    "
	for dep in ${DEPENDENCIES}; do
		dpkg -s "${dep}" > /dev/null 2>&1 || echo -n "${dep} "
	done
	echo
	echo "Install them running 'apt-get install' and retry"
	exit 1
}

###################################
### Check that URL is reachable ###
###################################
step "### Check that ${URL} is reachable ###"
ping -c1 -W1 $(sed 's:^.*\://\(.*$\):\1:' <<< ${URL}) > /dev/null 2>&1 && echo "OK" || fail "Error : ${URL} is not reachable"

########################
### Retrieve content ###
########################
step "### Retrieve project's issues ###"
CONTENT_FILE=$(mktemp /tmp/gitlab-extracter.XXXXXX.json)
HEADER_FILE=$(mktemp /tmp/gitlab-extracter.XXXXXX.header)

page_num=1
while [ ! -z "${page_num}" ]
do

	http_params="?per_page=100&page=${page_num}${AUTH}"
	curl -s -D ${HEADER_FILE} ${URL}/${GITLAB_API}/${ID}/issues${http_params} >> ${CONTENT_FILE}
	http_return_code=$(head -n 1 ${HEADER_FILE} | awk '{print $2}')
	grep -E '2[0-9]{2}' > /dev/null <<< ${http_return_code} || { cat ${HEADER_FILE}; fail "Error : Server returned HTTP status code ${http_return_code}"; }

	page_num=$(grep X-Next-Page: ${HEADER_FILE} | grep -oE '[0-9]+')

done

page_total=$(grep X-Total-Pages: ${HEADER_FILE} | grep -oE '[0-9]+')
entry_num=$(grep X-Total: ${HEADER_FILE} | grep -oE '[0-9]+')

echo "Retrieved ${entry_num} entries on ${page_total} pages"

######################
### Save JSON file ###
######################
[ -z "${OUTPUT}" ] || {
	[[ "${OUTPUT}" =~ ^.+\.json$ ]] || OUTPUT=${OUTPUT}.json
	step "### Saving JSON to ${OUTPUT} ###"

	cp ${CONTENT_FILE} ${OUTPUT} && echo "OK" || echo "Error : Unable to save file to ${OUTPUT}"
}

#######################
### Export CSV file ###
#######################
[ -z "${CSV_FILE}" ] || {
	[[ "${CSV_FILE}" =~ ^.+\.csv$ ]] || OUTPUT=${CSV_FILE}.csv
	step " ### Export CSV file to ${CSV_FILE} ###"

	sed -i 's/\\"/@@QUOTES@@/g' ${CONTENT_FILE}

	CSV_SEPARATOR=';'

	echo "Numéro${CSV_SEPARATOR}Titre${CSV_SEPARATOR}Statut${CSV_SEPARATOR}Milestone${CSV_SEPARATOR}Labels${CSV_SEPARATOR}Assignée${CSV_SEPARATOR}Auteur${CSV_SEPARATOR}Date création${CSV_SEPARATOR}Description" > ${CSV_FILE}

	# JSON filters can be implemented here as follow :
	#     | select(.labels | index(\"Mantis\") | not) ==> Remove all elements containing "Mantis" into 'labels' list
	#     | select(.labels | index(\"Bug\"))          ==> Keep only elements containing "Bug" into 'labels' list

	jq -r ".[]
	      | \"\(.iid)${CSV_SEPARATOR}\(.title)${CSV_SEPARATOR}\(.state)${CSV_SEPARATOR}\(.milestone.title)${CSV_SEPARATOR}\(.labels)${CSV_SEPARATOR}\(.assignee.name)${CSV_SEPARATOR}\(.author.name)${CSV_SEPARATOR}\(.created_at)${CSV_SEPARATOR}\\\"\(.description)\\\"\"" ${CONTENT_FILE} >> ${CSV_FILE} && echo "OK" || echo "Error : Unable to convert output to CSV file"

	sed -i 's/@@QUOTES@@/\\""/g' ${CSV_FILE}
}

#####################
### Print content ###
#####################
[ -z "${OUTPUT}" ] && BROWSE_FILE=${CONTENT_FILE} || BROWSE_FILE=${OUTPUT}
${BROWSE} && { sensible-browser ${BROWSE_FILE} || fail "Error : Unable to open file with default web browser"; } || [ -z "${OUTPUT}" ] && cat ${BROWSE_FILE}
echo

exit 0






