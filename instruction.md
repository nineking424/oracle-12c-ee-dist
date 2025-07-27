# Oracle Database 12c Enterprise Edition on Kubernetes

## 개요
이 문서는 Kubernetes 환경에서 Oracle Database 12c Enterprise Edition을 StatefulSet으로 배포하는 방법을 설명합니다.

## 사전 요구사항
- Kubernetes 클러스터 (1.19+)
- kubectl CLI 도구
- NFS StorageClass (nfs-client)
- 최소 4GB RAM과 20GB 스토리지를 제공할 수 있는 노드

## 배포 절차

### 1. Namespace 생성
```bash
kubectl create namespace oracle
```

### 2. 배포 파일 적용
```bash
# StatefulSet과 Headless Service 생성
kubectl apply -f statefulset.yaml

# NodePort와 LoadBalancer Service 생성
kubectl apply -f service.yaml
```

### 3. 배포 상태 확인
```bash
# Pod 상태 확인
kubectl get pods -n oracle

# Service 상태 확인
kubectl get svc -n oracle

# PVC 상태 확인
kubectl get pvc -n oracle
```

### 4. 데이터베이스 초기화 대기
Oracle 데이터베이스는 처음 시작 시 초기화에 약 10-15분이 소요됩니다.
```bash
# 로그 확인
kubectl logs -f oracle-db-0 -n oracle

# 초기화 완료 확인
kubectl exec oracle-db-0 -n oracle -- lsnrctl status
```

## 접속 정보

### 데이터베이스 연결
- **호스트**: `<노드IP>:30521` (NodePort) 또는 `<LoadBalancer IP>:1521`
- **SID**: ORCL
- **서비스명**: ORCL
- **사용자**: system / sys
- **비밀번호**: oracle

### Enterprise Manager
- **URL**: `http://<노드IP>:30080/em` 또는 `http://<LoadBalancer IP>:8080/em`
- **사용자**: sys
- **비밀번호**: oracle
- **Connect As**: SYSDBA

## 연결 예시

### SQLPlus로 연결
```bash
# 외부에서 연결
sqlplus system/oracle@<노드IP>:30521/ORCL

# Pod 내부에서 연결
kubectl exec -it oracle-db-0 -n oracle -- sqlplus system/oracle@localhost:1521/ORCL

# SYSDBA로 연결
kubectl exec -it oracle-db-0 -n oracle -- sqlplus sys/oracle@localhost:1521/ORCL as sysdba
```

### JDBC URL
```
jdbc:oracle:thin:@<노드IP>:30521:ORCL
jdbc:oracle:thin:@<노드IP>:30521/ORCL
```

### TNS Names 설정
```
ORCL =
  (DESCRIPTION =
    (ADDRESS_LIST =
      (ADDRESS = (PROTOCOL = TCP)(HOST = <노드IP>)(PORT = 30521))
    )
    (CONNECT_DATA =
      (SERVICE_NAME = ORCL)
    )
  )
```

## 테스트 스크립트 사용

포함된 테스트 스크립트로 데이터베이스 상태를 빠르게 확인할 수 있습니다:

```bash
# 기본 테스트 실행
./test-oracle-db.sh

# 상세 정보 표시 (디버그 모드)
./test-oracle-db.sh oracle oracle-db-0 true

# 다른 Pod 테스트
./test-oracle-db.sh oracle oracle-db-1
```

## 관리 작업

### 백업
```bash
# 데이터 디렉토리 백업
kubectl exec -n oracle oracle-db-0 -- tar -czf /tmp/backup.tar.gz /u01/app/oracle
kubectl cp oracle/oracle-db-0:/tmp/backup.tar.gz ./oracle-backup-$(date +%Y%m%d).tar.gz
```

### 데이터베이스 상태 확인
```bash
# 인스턴스 상태
kubectl exec oracle-db-0 -n oracle -- sqlplus -s system/oracle@localhost:1521/ORCL <<< "SELECT instance_name, status FROM v\$instance;"

# 테이블스페이스 사용량
kubectl exec oracle-db-0 -n oracle -- sqlplus -s system/oracle@localhost:1521/ORCL <<< "SELECT tablespace_name, ROUND(SUM(bytes)/1024/1024) MB FROM dba_data_files GROUP BY tablespace_name;"
```

### 스케일링
StatefulSet의 replicas를 조정하여 여러 인스턴스를 실행할 수 있습니다:
```bash
kubectl scale statefulset oracle-db -n oracle --replicas=2
```

### 리소스 조정
현재 설정은 메모리의 40%를 자동으로 할당합니다 (INIT_MEM_PST=40). 필요시 statefulset.yaml에서 환경변수를 수정하세요.

### 초기화 스크립트
컨테이너 시작 시 SQL 스크립트를 자동 실행하려면:
1. ConfigMap으로 스크립트 생성
2. `/oracle.init.d/` 디렉토리에 마운트

## 문제 해결

### Pod가 시작되지 않는 경우
```bash
# Pod 상세 정보 확인
kubectl describe pod oracle-db-0 -n oracle

# 로그 확인
kubectl logs oracle-db-0 -n oracle

# 이벤트 확인
kubectl get events -n oracle --sort-by='.lastTimestamp'
```

### 데이터베이스 연결 실패
```bash
# 리스너 상태 확인
kubectl exec oracle-db-0 -n oracle -- lsnrctl status

# 서비스 확인
kubectl exec oracle-db-0 -n oracle -- lsnrctl services

# 프로세스 확인
kubectl exec oracle-db-0 -n oracle -- ps aux | grep -E "(pmon|listener)"
```

### 메모리 부족
- 최소 2GB, 권장 4GB 이상의 메모리 필요
- SGA 크기는 약 4.8GB로 자동 설정됨

### 스토리지 부족
- PVC는 20GB로 설정됨
- 필요시 새 PVC 생성 후 데이터 마이그레이션 필요

### Enterprise Manager 접속 불가
```bash
# EM 포트 확인
kubectl exec oracle-db-0 -n oracle -- netstat -an | grep 8080

# EM 상태 확인
kubectl exec oracle-db-0 -n oracle -- emctl status dbconsole
```

## 보안 고려사항

### 비밀번호 관리
프로덕션 환경에서는 Kubernetes Secret 사용:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: oracle-credentials
  namespace: oracle
type: Opaque
stringData:
  oracle-pwd: "your-secure-password"
```

### 네트워크 정책
데이터베이스 접근 제한:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: oracle-db-policy
  namespace: oracle
spec:
  podSelector:
    matchLabels:
      app: oracle-db
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: allowed-namespace
    ports:
    - protocol: TCP
      port: 1521
```

### TLS/SSL 설정
프로덕션 환경에서는 Oracle Native Network Encryption 또는 SSL 설정을 권장합니다.

## 제거
```bash
# 서비스 삭제
kubectl delete -f service.yaml

# StatefulSet 삭제
kubectl delete -f statefulset.yaml

# PVC 삭제 (데이터 영구 삭제 주의!)
kubectl delete pvc -n oracle --all

# Namespace 삭제
kubectl delete namespace oracle
```

## 주의사항
- Oracle 12c EE는 라이선스가 필요한 상용 소프트웨어입니다
- 이 이미지는 테스트 및 개발 목적으로만 사용하세요
- 프로덕션 환경에서는 Oracle의 공식 라이선스를 구매하고 지원을 받으세요

## 참고 자료
- [Oracle Database 12c Documentation](https://docs.oracle.com/database/121/)
- [Kubernetes StatefulSet Documentation](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
- [Docker Image Source](https://github.com/padlik/oracle-12c)