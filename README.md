# rundeck-tools
Rundeck 관련 tools 및 문서

### 업데이트 내역
- 25.08 update v0.1 : Rundeck 설치 스크립트

### 참고
- Rundeck
<br>rundeck 관련 커널 추천 값 #1: [링크](https://docs.rundeck.com/docs/administration/maintenance/tuning-rundeck.html)

## 설치 방법
### install_rundeck.sh
Usage: ./install_rundeck.sh [Options]<br>
Options:<br>
-i, --install  : Install Rundeck<br>
-r, --remove   : Remove  Rundeck<br>
-u, --user     [ STRING ] : Rundeck User (deafult: ${RDECK_USER})<br>
-p, --path     [ STRING ] : Rundeck Path (deafult: ${RDECK_PATH})<br>
    --ip       [ STRING ] : Rundeck server ip (default: ${RDECK_IP})<br>
-v, --version  [ STRING ] : Rundeck Version name (default: ${RDECK_VER})<br>
--min-mem      [ INT Gb ] : JVM Heap Minimum size (default: ${ELK_MEM_MIN}g)<br>
--max-mem      [ INT Gb ] : JVM Heap Maximum size (default: ${ELK_MAX_MIN}g)<br>
-h, --help     : Script help<br>

> Rundeck 설치하는 경우
Exmaple: ./install_rundeck.sh -i -u app -i 192.168.1.1 -p /APP -v 5.14.1-20250818
1. Data Path 경로 생성
2. 요청한 서비스의 바이너리 파일 다운로드, 링크 설정
3. linux 커널 값 설정
5. Data path내 필요한 디렉토리 생성 및 기본 Config 설정
6. 서비스 기동 스크립트 생성
7. 생성된 디렉토리 내 서비스유저 권한으로 변경