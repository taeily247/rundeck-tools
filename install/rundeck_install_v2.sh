#!/bin/bash

##### Enviroment - Common
RDECK_PATH="/APP"
RDECK_VER="${RDECK_VER}"
RDECK_USER="app"
RDECK_MEM_MIN=$(awk '/MemTotal/ {printf "%.0f\n", (($2/1024/1024)*90)/100}' /proc/meminfo)
RDECK_MEM_MAX=$(awk '/MemTotal/ {printf "%.0f\n", (($2/1024/1024)*90)/100}' /proc/meminfo)
# RDECK_VER="5.14.1-20250818"

JAVA_PATH=$(command -v java)
PKGS=()

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
--min-mem      [ INT Gb ] : JVM Heap Minimum size (default: ${ELK_MEM_MIN}g)
--max-mem      [ INT Gb ] : JVM Heap Maximum size (default: ${ELK_MAX_MIN}g)
-h, --help     : Script help
EOF
    exit 0
}

function set_opts() {
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

function installPacakges() {
    if [ ! -f ${RDECK_PATH}/rundeck-${RDECK_VER}.war ]; then
        runCommand "wget https://packagecloud.io/pagerduty/rundeck/packages/java/org.rundeck/rundeck-${RDECK_VER}.war/artifacts/rundeck-${RDECK_VER}.war/download?distro_version_id=167 \
        -O ${RDECK_PATH}/rundeck-${RDECK_VER}.war"
        return 0
    else
        logging "SKIP" "Already download ${RDECK_PATH}/rundeck-${RDECK_VER}.war"
        return 0
    fi
}


function setRundeck() {
    if [ ! -f /etc/systemd/system/rundeck.service ]; then
        runCommand "cat <<EOF >/etc/systemd/system/rundeck.service
[Unit]
Description=Rundeck

[Service]
Type=simple
SyslogLevel=debug
User=root
ExecStart=${JAVA_PATH} -Xmx4g -Xms1g -XX:MaxMetaspaceSize=256m -jar ${RDECK_PATH}/rundeck-${RDECK_VER}.war
# ExecStart=${JAVA_PATH} -Xmx1024m -Xms256m -XX:MaxMetaspaceSize=256m -server -jar ${RDECK_PATH}/rundeck-${RDECK_VER}.war
KillSignal=SIGTERM
KillMode=mixed
WorkingDirectory=${RDECK_PATH}

LimitNOFILE=65535
LimitNPROC=65535
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

    runCommand "sustemctl daemon-reload"

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
        runCommand "
cat <<EOF >/etc/security/limits.d/${RDECK_USER}.conf
${RDECK_USER}       soft    nofile         65536
${RDECK_USER}       hard    nofile         65536
${RDECK_USER}       soft    nproc          65536
${RDECK_USER}       hard    nproc          65536
${RDECK_USER}       soft    memlock        unlimited
${RDECK_USER}       hard    memlock        unlimited
EOF"
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
    set_opts "$@"

    case ${MODE} in
        "install" )
            if [[ -z ${RDECK_PATH} ]] && [[ -z ${RDECK_IP} ]]; then
                help
            fi
            install_rundeckw
            if [ $? -eq 0 ]; then
                setup_rundeck_config
                if [ $? -eq 0 ]; then
                    runCommand "systemctl stop rundeck"
                    logging "INFO" "Install rundeck completed, excute command [ systemctl start rundeck ]"
                fi
            else
                logging "ERROR" "Install rundeck failed."
            fi
        ;;
        "remove"  )
            if [ -z ${RDECK_PATH} ]; then
                help
            fi

            remove_rundeck
            if [ $? -eq 0 ]; then
                unsetup_rundeck_config
                if [ $? -eq 0 ]; then
                    runCommand "systemctl stop rundeck"
                    logging "INFO" "Remove rundeck completed"
                fi
            else
                logging "ERROR" "Remove rundeck failed."
            fi
        ;;
        # *         ) help     ; exit 0 ;;
    esac
}
main $*