# Oracle 12c Enterprise Edition Kubernetes Deployment

이 프로젝트는 Oracle 12c Enterprise Edition 데이터베이스를 Kubernetes 클러스터에 배포하기 위한 설정 파일들을 포함합니다.

## 구성 요소

- **StatefulSet**: Oracle 데이터베이스 인스턴스를 안정적으로 관리
- **Service**: NodePort와 LoadBalancer 서비스로 외부 접속 제공
- **PersistentVolume**: NFS 스토리지를 사용한 영구 데이터 저장
- **테스트 스크립트**: 데이터베이스 상태 확인 자동화

## 사전 요구사항

- Kubernetes 클러스터 (v1.19+)
- NFS 스토리지 클래스 (nfs-client)
- kubectl CLI 도구

## 설치 방법

### 1. 네임스페이스 생성
```bash
kubectl create namespace oracle
```

### 2. 리소스 배포
```bash
# StatefulSet과 Headless 서비스 배포
kubectl apply -f statefulset.yaml

# 외부 접속용 서비스 배포
kubectl apply -f service.yaml
```

### 3. 배포 상태 확인
```bash
# Pod 상태 확인
kubectl get pods -n oracle

# 서비스 확인
kubectl get svc -n oracle
```

## 접속 정보

### 데이터베이스 접속
- **호스트**: NodePort 서비스 사용 시 `<노드IP>:30521`
- **SID**: ORCL
- **서비스명**: ORCL
- **사용자명**: system / sys
- **비밀번호**: oracle

### Enterprise Manager
- **URL**: `http://<노드IP>:30080/em`
- **사용자**: sys
- **비밀번호**: oracle
- **Sysdba**: true

### SQLPlus 접속 예시
```bash
# Pod 내부에서 직접 접속
kubectl exec -it oracle-db-0 -n oracle -- sqlplus system/oracle@localhost:1521/ORCL

# 외부에서 접속 (NodePort 사용)
sqlplus system/oracle@<노드IP>:30521/ORCL
```

## 테스트 스크립트 사용

데이터베이스 상태를 확인하는 자동화된 테스트 스크립트가 포함되어 있습니다.

```bash
# 기본 실행
./test-oracle-db.sh

# 디버그 모드 (상세 정보 표시)
./test-oracle-db.sh oracle oracle-db-0 true

# 다른 Pod 테스트
./test-oracle-db.sh oracle oracle-db-1
```

## 구성 상세

### StatefulSet 설정
- **이미지**: absolutapps/oracle-12c-ee:latest
- **리소스**: 메모리 40% 자동 할당 (INIT_MEM_PST=40)
- **볼륨**: /u01/app/oracle에 20GB PVC 마운트
- **보안**: privileged 모드 활성화 (Oracle 요구사항)

### 포트 구성
- **1521**: Oracle Listener (데이터베이스 접속)
- **8080**: Enterprise Manager Console

### 환경 변수
- `ORACLE_SID`: Oracle 시스템 식별자 (기본값: ORCL)
- `SERVICE_NAME`: 데이터베이스 서비스명 (기본값: ORCL)
- `INIT_MEM_PST`: 메모리 할당 비율 (기본값: 40%)

## 고급 설정

### 초기화 스크립트
`/oracle.init.d/` 디렉토리에 SQL 스크립트를 배치하면 컨테이너 시작 시 자동으로 실행됩니다.

### 스케일링
StatefulSet의 replicas를 조정하여 여러 Oracle 인스턴스를 실행할 수 있습니다:
```bash
kubectl scale statefulset oracle-db -n oracle --replicas=2
```

## 문제 해결

### Pod가 시작되지 않는 경우
```bash
# Pod 로그 확인
kubectl logs oracle-db-0 -n oracle

# Pod 상세 정보 확인
kubectl describe pod oracle-db-0 -n oracle
```

### 데이터베이스 접속 실패
```bash
# 리스너 상태 확인
kubectl exec oracle-db-0 -n oracle -- lsnrctl status

# 데이터베이스 상태 확인
./test-oracle-db.sh oracle oracle-db-0 true
```

### 스토리지 문제
```bash
# PVC 상태 확인
kubectl get pvc -n oracle

# PV 상태 확인
kubectl get pv
```

## 주의사항

- Oracle 12c EE는 라이선스가 필요한 상용 소프트웨어입니다
- 프로덕션 환경에서는 적절한 리소스 제한과 보안 설정을 적용하세요
- 데이터베이스 백업 전략을 수립하고 정기적으로 백업을 수행하세요

## 참고 자료

- [Oracle Database 12c Documentation](https://docs.oracle.com/database/121/)
- [Kubernetes StatefulSet Documentation](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
- [Docker Image Source](https://github.com/padlik/oracle-12c)