# Oracle Database 12c Enterprise Edition on Kubernetes

## 개요
이 문서는 Kubernetes 환경에서 Oracle Database 12c Enterprise Edition을 배포하는 방법을 설명합니다.

## 사전 요구사항
- Kubernetes 클러스터 (1.19+)
- kubectl CLI 도구
- 최소 4GB RAM과 20GB 스토리지를 제공할 수 있는 노드

## 배포 절차

### 1. Namespace 생성
```bash
kubectl create namespace oracle
```

### 2. 배포 파일 적용
```bash
# Deployment와 PVC 생성
kubectl apply -f deployment.yaml

# Service 생성
kubectl apply -f service.yaml
```

### 3. 배포 상태 확인
```bash
# Pod 상태 확인
kubectl get pods -n oracle

# Service 상태 확인
kubectl get svc -n oracle
```

### 4. 데이터베이스 초기화 대기
Oracle 데이터베이스는 처음 시작 시 초기화에 약 10-15분이 소요됩니다.
```bash
# 로그 확인
kubectl logs -f deployment/oracle-db -n oracle
```

## 접속 정보

### 데이터베이스 연결
- **호스트**: `<노드IP>:30521` (NodePort) 또는 `<LoadBalancer IP>:1521`
- **SID**: ORCLCDB
- **PDB**: ORCLPDB1
- **사용자**: system
- **비밀번호**: Oracle123

### Enterprise Manager
- **URL**: `http://<노드IP>:30500/em` 또는 `http://<LoadBalancer IP>:5500/em`
- **사용자**: system
- **비밀번호**: Oracle123

## 연결 예시

### SQLPlus로 연결
```bash
sqlplus system/Oracle123@<노드IP>:30521/ORCLCDB
```

### JDBC URL
```
jdbc:oracle:thin:@<노드IP>:30521:ORCLCDB
```

## 관리 작업

### 백업
```bash
# PVC 데이터 백업
kubectl exec -n oracle deployment/oracle-db -- tar -czf /tmp/backup.tar.gz /opt/oracle/oradata
kubectl cp oracle/oracle-db-<pod-id>:/tmp/backup.tar.gz ./oracle-backup.tar.gz
```

### 스케일링
단일 인스턴스로만 실행하는 것을 권장합니다. Oracle RAC가 필요한 경우 별도의 설정이 필요합니다.

### 리소스 조정
deployment.yaml의 resources 섹션을 수정하여 CPU와 메모리를 조정할 수 있습니다.

## 문제 해결

### Pod가 시작되지 않는 경우
```bash
kubectl describe pod -n oracle
kubectl logs -n oracle <pod-name>
```

### 메모리 부족
최소 2GB, 권장 4GB 이상의 메모리를 할당하세요.

### 스토리지 부족
PVC 크기를 늘려야 할 수 있습니다. StorageClass가 확장을 지원하는지 확인하세요.

## 보안 고려사항
- 프로덕션 환경에서는 비밀번호를 Kubernetes Secret으로 관리하세요
- 네트워크 정책을 사용하여 데이터베이스 접근을 제한하세요
- TLS/SSL 설정을 고려하세요

## 제거
```bash
kubectl delete -f service.yaml
kubectl delete -f deployment.yaml
kubectl delete namespace oracle
```