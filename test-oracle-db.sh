#!/bin/bash

# Oracle Database 테스트 스크립트
# 사용법: ./test-oracle-db.sh [NAMESPACE] [POD_NAME] [VERBOSE]

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# 기본 설정
NAMESPACE="${1:-oracle}"
POD_NAME="${2:-oracle-db-0}"
VERBOSE="${3:-false}"
USERNAME="system"
PASSWORD="oracle"
SERVICE="ORCL"

# 헤더 출력
print_header() {
    local width=50
    local line=$(printf '=%.0s' $(seq 1 $width))
    echo -e "\n${MAGENTA}${line}${NC}"
    echo -e "${MAGENTA}${BOLD}$(printf '%*s' $(((width + ${#1}) / 2)) "$1")${NC}"
    echo -e "${MAGENTA}${line}${NC}"
}

# 섹션 구분선
print_section() {
    echo -e "\n${CYAN}━━━ $1 ━━━${NC}"
}

# 진행 상황 표시
print_progress() {
    echo -e "\n${YELLOW}⏳ $1...${NC}"
}

# 함수: 디버그 출력
debug() {
    if [ "$VERBOSE" = "true" ]; then
        echo -e "${CYAN}[DEBUG]${NC} $1" >&2
    fi
}

print_header "Oracle Database 테스트 스크립트"
echo -e "\n📍 ${BOLD}Namespace:${NC} ${GREEN}$NAMESPACE${NC}"
echo -e "🗄️  ${BOLD}Pod Name:${NC} ${GREEN}$POD_NAME${NC}"
echo -e "🔧 ${BOLD}Verbose mode:${NC} ${GREEN}$VERBOSE${NC}"
echo -e "🕐 ${BOLD}실행 시간:${NC} $(date '+%Y-%m-%d %H:%M:%S')"

# 함수: SQL 실행 및 결과 출력
execute_sql() {
    local query=$1
    local description=$2
    local show_output=${3:-true}
    
    echo -e "\n${YELLOW}▶ ${description}${NC}"
    echo -e "  ${DIM}SQL: $query${NC}"
    
    debug "SQL 실행: $query"
    
    # SQL 실행
    result=$(kubectl exec $POD_NAME -n $NAMESPACE -- bash -c "echo '$query' | sqlplus -s $USERNAME/$PASSWORD@localhost:1521/$SERVICE" 2>&1)
    exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        echo -e "  ${GREEN}✅ 성공${NC}"
    else
        echo -e "  ${RED}❌ 실패${NC}"
        if [ "$VERBOSE" = "true" ]; then
            echo -e "${RED}오류: $result${NC}"
        fi
        return 1
    fi
    
    debug "SQL 결과: $result"
    
    # 결과 출력
    if [ "$show_output" = "true" ] && [ ! -z "$result" ]; then
        echo -e "\n${DIM}실행 결과:${NC}"
        echo "$result" | sed 's/^/  /'
    fi
}

# 함수: Pod 상태 확인
check_pod_status() {
    local pod_status=$(kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.status.phase}' 2>&1)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Pod를 찾을 수 없습니다: $POD_NAME (namespace: $NAMESPACE)${NC}"
        echo -e "\n${YELLOW}💡 해결 방법:${NC}"
        echo -e "  • 현재 Pod 확인: ${CYAN}kubectl get pods -n $NAMESPACE${NC}"
        echo -e "  • 다른 Pod로 테스트: ${CYAN}$0 <namespace> <pod-name>${NC}"
        return 1
    fi
    
    if [ "$pod_status" != "Running" ]; then
        echo -e "${RED}❌ Pod가 실행 중이 아닙니다. 현재 상태: $pod_status${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✅ Pod 상태 정상: $pod_status${NC}"
    return 0
}

# 1. Pod 상태 확인
print_section "Pod 상태 확인"
print_progress "Pod 상태 확인 중"
if ! check_pod_status; then
    exit 1
fi

# 2. 데이터베이스 연결 테스트
print_section "데이터베이스 연결 테스트"
print_progress "Oracle 데이터베이스 연결 테스트 중"

# 간단한 연결 테스트
if kubectl exec $POD_NAME -n $NAMESPACE -- bash -c "echo 'SELECT 1 FROM DUAL;' | sqlplus -s $USERNAME/$PASSWORD@localhost:1521/$SERVICE" &>/dev/null; then
    echo -e "${GREEN}✅ 데이터베이스 연결 성공${NC}"
else
    echo -e "${RED}❌ 데이터베이스 연결 실패${NC}"
    echo -e "\n${YELLOW}💡 해결 방법:${NC}"
    echo -e "  • Pod 로그 확인: ${CYAN}kubectl logs $POD_NAME -n $NAMESPACE${NC}"
    echo -e "  • 환경 변수 확인: ${CYAN}kubectl describe pod $POD_NAME -n $NAMESPACE | grep -A 10 Environment${NC}"
    exit 1
fi

# 3. 인스턴스 정보
print_section "데이터베이스 인스턴스 정보"
execute_sql "SELECT instance_name, host_name, version, status, database_status FROM v\$instance;" "인스턴스 상세 정보"

# 4. 데이터베이스 정보
print_section "데이터베이스 정보"
execute_sql "SELECT name, open_mode, log_mode, flashback_on FROM v\$database;" "데이터베이스 상태"

# 5. 테이블스페이스 정보
print_section "테이블스페이스 정보"
execute_sql 'SELECT tablespace_name, status, contents, extent_management FROM dba_tablespaces WHERE tablespace_name NOT LIKE '\''UNDO%'\'' ORDER BY tablespace_name;' "테이블스페이스 목록"

# 6. 데이터파일 사용량
print_section "스토리지 사용량"
execute_sql "SELECT tablespace_name, ROUND(SUM(bytes)/1024/1024, 2) AS size_mb, ROUND(SUM(maxbytes)/1024/1024, 2) AS max_size_mb FROM dba_data_files GROUP BY tablespace_name ORDER BY tablespace_name;" "데이터파일 크기"

# 7. 메모리 정보
print_section "메모리 구성"
execute_sql "SELECT name, ROUND(value/1024/1024, 2) AS size_mb FROM v\$sga ORDER BY name;" "SGA 구성요소"

# 8. 세션 정보
print_section "세션 정보"
execute_sql 'SELECT COUNT(*) AS total_sessions, SUM(CASE WHEN status = '\''ACTIVE'\'' THEN 1 ELSE 0 END) AS active_sessions, SUM(CASE WHEN type = '\''USER'\'' THEN 1 ELSE 0 END) AS user_sessions FROM v$session;' "세션 통계"

# 9. 사용자 정보
print_section "데이터베이스 사용자"
execute_sql "SELECT username, account_status, created, profile FROM dba_users WHERE username NOT IN ('SYS','SYSTEM','DBSNMP','APPQOSSYS','ORACLE_OCM','DIP','OUTLN','XDB','ANONYMOUS') ORDER BY username;" "사용자 목록"

# 10. 현재 실행 중인 쿼리
if [ "$VERBOSE" = "true" ]; then
    print_section "현재 실행 중인 쿼리"
    execute_sql 'SELECT s.sid, s.serial#, s.username, s.status, s.sql_id, SUBSTR(q.sql_text, 1, 50) AS sql_text_preview FROM v$session s LEFT JOIN v$sql q ON s.sql_id = q.sql_id WHERE s.type = '\''USER'\'' AND s.username IS NOT NULL ORDER BY s.status DESC, s.sid;' "활성 세션 및 SQL"
fi

# 11. 리스너 상태
print_section "리스너 상태"
echo -e "\n${YELLOW}▶ 리스너 상태 확인${NC}"
listener_status=$(kubectl exec $POD_NAME -n $NAMESPACE -- lsnrctl status 2>&1 | grep -E "(READY|Service|Listening)" | head -10)
if [ $? -eq 0 ]; then
    echo -e "  ${GREEN}✅ 리스너 실행 중${NC}"
    if [ "$VERBOSE" = "true" ]; then
        echo -e "\n${DIM}리스너 정보:${NC}"
        echo "$listener_status" | sed 's/^/  /'
    fi
else
    echo -e "  ${RED}❌ 리스너 상태 확인 실패${NC}"
fi

# 12. 테스트 테이블 생성 및 삭제 (옵션)
if [ "$VERBOSE" = "true" ]; then
    print_section "데이터베이스 쓰기 테스트"
    
    # 테스트 테이블 생성
    execute_sql "CREATE TABLE test_table (id NUMBER PRIMARY KEY, name VARCHAR2(50), created_at DATE DEFAULT SYSDATE);" "테스트 테이블 생성" false
    
    # 데이터 삽입
    execute_sql 'INSERT INTO test_table (id, name) VALUES (1, '\''Test Record'\''); COMMIT;' "테스트 데이터 삽입" false
    
    # 데이터 조회
    execute_sql "SELECT * FROM test_table;" "테스트 데이터 조회"
    
    # 테스트 테이블 삭제
    execute_sql "DROP TABLE test_table;" "테스트 테이블 삭제" false
fi

# 요약
print_header "테스트 완료"
debug "모든 테스트 완료"
echo -e "\n${GREEN}✅ 모든 데이터베이스 테스트가 완료되었습니다!${NC}"
echo -e "\n${BOLD}📌 추가 옵션:${NC}"
echo -e "  ${CYAN}•${NC} 디버그 모드: ${DIM}$0 <namespace> <pod-name> true${NC}"
echo -e "  ${CYAN}•${NC} 다른 Pod: ${DIM}$0 oracle oracle-db-1${NC}"
echo -e "  ${CYAN}•${NC} SQL*Plus 직접 접속: ${DIM}kubectl exec -it $POD_NAME -n $NAMESPACE -- sqlplus $USERNAME/$PASSWORD@localhost:1521/$SERVICE${NC}"
echo -e "\n${BOLD}📖 유용한 명령어:${NC}"
echo -e "  ${CYAN}•${NC} Pod 로그 확인: ${DIM}kubectl logs $POD_NAME -n $NAMESPACE${NC}"
echo -e "  ${CYAN}•${NC} Pod 상태 확인: ${DIM}kubectl describe pod $POD_NAME -n $NAMESPACE${NC}"
echo -e "  ${CYAN}•${NC} 모든 Pod 확인: ${DIM}kubectl get pods -n $NAMESPACE${NC}"
echo ""