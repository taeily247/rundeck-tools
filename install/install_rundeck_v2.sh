#!/bin/bash

##### Enviroment - Common
RDECK_PATH="/APP"
RDECK_VER="5.14.1-20250818"
RDECK_USER="app"
RDECK_IP="$(ifconfig | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p')"
RDECK_MEM_MIN=$(awk '/MemTotal/ {printf "%.0f\n", (($2/1024/1024)*90)/100}' /proc/meminfo)
RDECK_MEM_MAX=$(awk '/MemTotal/ {printf "%.0f\n", (($2/1024/1024)*90)/100}' /proc/meminfo)

JAVA_PATH=$(command -v java)
PKGS=()

function checkCommand() {
    # wget = wget
    # ifconfig = net-tools
    # java = java-11-openjdk-devel
    # java = java-17-openjdk-devel
    _command=('wget' 'ifconfig' 'java')
    for i in ${_command[@]}; do
        command -v ${i} >/dev/null
        [ $? -eq 1 ] && { logging "ERROR" "Command not found [ ${i} ]"; exit 1; }
    done
}

function runCommand() {
    _command=$@
    logging "CMD" "$@"
    eval "${_command}" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        logging "OK"
        return 0
    else
        logging "FAIL"
        return 1
    fi
}

function logging() {
    _log_command="tee -a ${SCRIPT_LOG}/script_$(date +%y%m%d).log"

    _timestamp=$(date "+%y%m%d %H:%M:%S.%3N")
    _type=$1
    _msg=$2

    # printf "%-*s | %s\n" ${STR_LEGNTH} "Server Serial" "Unknown" |tee -a ${LOG_FILE} >/dev/null
    case ${_type} in
        "OK"    ) printf "%s\n" "Command OK"   ;;
        "FAIL"  ) printf "%s\n" "Command FAIL" ;;
        "CMD"   ) printf "%s | %-*s | %s => " "${_timestamp}" 7 "${_type}" "${_msg}"     ;;
        "INFO"  ) printf "%s | %-*s | %s\n" "${_timestamp}" 7 "${_type}" "${_msg}"       ;;
        "WARR"  ) printf "%s | %-*s | %s\n" "${_timestamp}" 7 "${_type}" "${_msg}"       ;;
        "SKIP"  ) printf "%s | %-*s | %s\n" "${_timestamp}" 7 "${_type}" "${_msg}"       ;;
        "ERROR" ) printf "%s | %-*s | %s\n" "${_timestamp}" 7 "${_type}" "${_msg}"       ;;
    esac
}

function help() {
    cat <<EOF
Usage: $0 [Options]
Options:
-i, --install  : Install Rundeck
-r, --remove   : Remove  Rundeck
-u, --user     [ STRING ] : Rundeck User (deafult: ${RDECK_USER})
-p, --path     [ STRING ] : Rundeck Path (deafult: ${RDECK_PATH})
    --ip       [ STRING ] : Rundeck server ip (default: ${RDECK_IP})
-v, --version  [ STRING ] : Rundeck Version name (default: ${RDECK_VER})
--min-mem      [ INT Gb ] : JVM Heap Minimum size (default: ${RDECK_MEM_MIN}g)
--max-mem      [ INT Gb ] : JVM Heap Maximum size (default: ${RDECK_MEM_MAX}g)
-h, --help     : Script help
EOF
    exit 0
}

function setOptions() {
    arguments=$(getopt --options p:u:irh \
    --longoptions path:,user:,ip:,min-mem:,max-mem:,install,remove,help \
    --name $(basename $0) \
    -- "$@")

    eval set -- "${arguments}"
    while true; do
        case "$1" in
            -i | --install  ) MODE="install"   ; shift   ;;
            -r | --remove   ) MODE="remove"    ; shift   ;;
            -u | --user     ) RDECK_USER=$2    ; shift 2 ;;
            -p | --path     ) RDECK_PATH=$2    ; shift 2 ;;
                 --ip       ) RDECK_IP=$2      ; shift 2 ;;
            --min-mem       ) RDECK_MEM_MIN=$2 ; shift 2 ;;
            --max-mem       ) RDECK_MEM_MAX=$2 ; shift 2 ;;
            -h | --help     ) help             ;;
            --              ) shift            ; break   ;;
            ?               ) help             ;;
        esac
    done

    shift $((OPTIND-1))
}

function instPackages() {
    if [ ! -f ${RDECK_PATH}/rundeck-${RDECK_VER}.war ]; then
        runCommand "wget https://packagecloud.io/pagerduty/rundeck/packages/java/org.rundeck/rundeck-${RDECK_VER}.war/artifacts/rundeck-${RDECK_VER}.war/download?distro_version_id=167 \
        -O ${RDECK_PATH}/rundeck-${RDECK_VER}.war"
        return 0
    else
        logging "SKIP" "Already download ${RDECK_PATH}/rundeck-${RDECK_VER}.war"
        return 0
    fi
}


function setPackages() {
    if [ ! -f /etc/systemd/system/rundeck.service ]; then
        runCommand "cat <<EOF >/etc/systemd/system/rundeck.service
[Unit]
Description=Rundeck

[Service]
Type=simple
SyslogLevel=info
User=${RDECK_USER}
ExecStart=${JAVA_PATH} -Xmx${RDECK_MEM_MAX}g -Xms${RDECK_MEM_MAX}g -XX:MaxMetaspaceSize=512m -jar ${RDECK_PATH}/rundeck-${RDECK_VER}.war
KillSignal=SIGTERM
KillMode=mixed
WorkingDirectory=${RDECK_PATH}

TasksMax=infinity
ExecReload=/bin/kill -HUP $MAINPID
TimeoutStopSec=120
SyslogIdentifier=IRI
Restart=on-failure
RestartSec=120

[Install]
WantedBy=multi-user.target
EOF"
    else
        logging "SKIP" "Already create file /etc/systmed/system/rundeck.service"
    fi

    runCommand "systemctl daemon-reload"
    runCommand "systemctl start rundeck"
    [ $? -eq 0 ] && { logging "INFO" "Initalize rundeck service (5s).."; sleep 10; }
    
    runCommand "systemctl stop rundeck"
    [ $? -eq 0 ] && logging "INFO" "OK setup initalization next to setup rundeck"

    if [ ! $(grep -q "grails.serverURL=http://${RDECK_IP}:4440" ${RDECK_PATH}/server/config/rundeck-config.properties) ]; then
        runCommand "cp -p ${RDECK_PATH}/server/config/rundeck-config.properties ${RDECK_PATH}/server/config/rundeck-config.properties.bk_$(date +%y%m%d_%H%M%S)"
        runCommand "sed -i 's/server.address/#&/g' ${RDECK_PATH}/server/config/rundeck-config.properties"
        runCommand "sed -i '/^#server.address/a\server.address=0.0.0.0' ${RDECK_PATH}/server/config/rundeck-config.properties"
        runCommand "sed -i 's/grails.serverURL/#&/g' ${RDECK_PATH}/server/config/rundeck-config.properties"
        runCommand "sed -i '/^#grails.serverURL/a\grails.serverURL=http://${RDECK_IP}:4440' ${RDECK_PATH}/server/config/rundeck-config.properties"
    else
        logging "SKIP" "Already config file ${RDECK_PATH}/server/config/rundeck-config.properties"
    fi

    if [ ! -f /etc/security/limits.d/${RDECK_USER}.conf ]; then
        runCommand "cat <<EOF >/etc/security/limits.d/${RDECK_USER}.conf
${RDECK_USER}       soft    nofile         65536
${RDECK_USER}       hard    nofile         65536
${RDECK_USER}       soft    nproc          65536
${RDECK_USER}       hard    nproc          65536
${RDECK_USER}       soft    memlock        unlimited
${RDECK_USER}       hard    memlock        unlimited
EOF"
    fi
}

function remove_rundeck() {
    runCommand "systemctl stop rundeck"
    if [ -f /etc/systmed/system/rundeck.service ]; then
        runCommand "rm -f /etc/systmed/system/rundeck.service"
    fi

    if [ -d /APP/rundeck.d ]; then
        read -p "Remove rundeck directory(Path: ${RDECK_PATH})? ((Y|n): " _answer
        case ${_answer} in
        	[Yy]* ) runCommand "rm -rf /APP/rundeck.d"; [ $? -eq 0 ] && return 0 ;;
        	[Nn]* ) return 0 ;;
        esac
    else
        logging "SKIP" "Already remove directory ${RDECK_PATH}"
        return 0
    fi
}

function main() {
    [ $# -eq 0 ] && help
    setOptions "$@"
    checkCommand

    if [ ! -d ${RDECK_PATH} ]; then
        runCommand "mkdir ${RDECK_PATH}"
        [ $? -eq 1 ] && { logging "ERROR" "fail create directory ${RDECK_PATH}"; exit 1; }
    fi
    
    case ${MODE} in
        "install" )
            instPackages
            [ $? -eq 1 ] && exit 0

            setPackages "${i}"
            runCommand "chown -R ${RDECK_USER} ${RDECK_PATH}/*"
        ;;
        "remove"  ) echo "remote"  ; exit 0 ;;
        *         ) help           ; exit 0 ;;
    esac
}
main $*