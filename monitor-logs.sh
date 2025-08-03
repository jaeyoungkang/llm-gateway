#!/bin/bash

# Cloud Run 로그 모니터링 스크립트
# 사용법: ./monitor-logs.sh <SERVICE_NAME> [PROJECT_ID] [REGION]

set -e

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 파라미터 확인
if [ -z "$1" ]; then
    echo -e "${RED}❌ 사용법: $0 <SERVICE_NAME> [PROJECT_ID] [REGION]${NC}"
    echo -e "${YELLOW}예시: $0 llm-gateway${NC}"
    echo -e "${YELLOW}예시: $0 llm-gateway my-project asia-northeast3${NC}"
    exit 1
fi

SERVICE_NAME="$1"
PROJECT_ID="${2:-$(gcloud config get-value project 2>/dev/null)}"
REGION="${3:-asia-northeast3}"

# gcloud 설치 확인
if ! command -v gcloud >/dev/null 2>&1; then
    echo -e "${RED}❌ gcloud CLI가 설치되지 않았습니다.${NC}"
    echo -e "${YELLOW}설치 가이드: https://cloud.google.com/sdk/docs/install${NC}"
    exit 1
fi

# 프로젝트 ID 확인
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}❌ GCP 프로젝트 ID를 찾을 수 없습니다.${NC}"
    echo -e "${YELLOW}gcloud config set project YOUR_PROJECT_ID로 설정하거나${NC}"
    echo -e "${YELLOW}스크립트 실행 시 프로젝트 ID를 직접 지정해주세요.${NC}"
    exit 1
fi

echo -e "${BLUE}📊 Cloud Run 로그 모니터링 시작${NC}"
echo -e "${BLUE}🏷️  서비스: ${SERVICE_NAME}${NC}"
echo -e "${BLUE}📍 프로젝트: ${PROJECT_ID}${NC}"
echo -e "${BLUE}🌏 리전: ${REGION}${NC}"
echo -e "${CYAN}💡 Ctrl+C로 모니터링을 중단할 수 있습니다.${NC}"
echo ""

# 서비스 존재 확인
echo -n "🔍 서비스 존재 확인 중... "
if gcloud run services describe "$SERVICE_NAME" --region="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
    echo -e "${GREEN}✅ 서비스 발견${NC}"
else
    echo -e "${RED}❌ 서비스를 찾을 수 없습니다${NC}"
    echo -e "${YELLOW}사용 가능한 서비스 목록:${NC}"
    gcloud run services list --project="$PROJECT_ID" 2>/dev/null || echo "서비스 목록을 가져올 수 없습니다."
    exit 1
fi

echo ""
echo -e "${GREEN}🚀 실시간 로그 스트리밍 시작...${NC}"
echo "$(date '+%Y-%m-%d %H:%M:%S') - 로그 모니터링 시작"
echo "----------------------------------------"

# 로그 필터링 및 포맷팅 함수
format_log() {
    while IFS= read -r line; do
        # 타임스탬프 추출 및 포맷팅
        timestamp=$(echo "$line" | grep -o '[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}T[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}' | head -1)
        
        if [ -n "$timestamp" ]; then
            # 로그 레벨에 따른 색상 적용
            if echo "$line" | grep -q "ERROR\|CRITICAL\|Exception\|Traceback"; then
                echo -e "${RED}[ERROR]${NC} $timestamp - $line"
            elif echo "$line" | grep -q "WARNING\|WARN"; then
                echo -e "${YELLOW}[WARN]${NC} $timestamp - $line"
            elif echo "$line" | grep -q "INFO"; then
                echo -e "${GREEN}[INFO]${NC} $timestamp - $line"
            elif echo "$line" | grep -q "DEBUG"; then
                echo -e "${CYAN}[DEBUG]${NC} $timestamp - $line"
            else
                echo -e "${NC}[LOG]${NC} $timestamp - $line"
            fi
        else
            # 타임스탬프가 없는 경우
            if echo "$line" | grep -q "ERROR\|CRITICAL\|Exception\|Traceback"; then
                echo -e "${RED}[ERROR]${NC} $(date '+%H:%M:%S') - $line"
            elif echo "$line" | grep -q "WARNING\|WARN"; then
                echo -e "${YELLOW}[WARN]${NC} $(date '+%H:%M:%S') - $line"
            else
                echo -e "${NC}[LOG]${NC} $(date '+%H:%M:%S') - $line"
            fi
        fi
    done
}

# 인터럽트 핸들러
cleanup() {
    echo ""
    echo -e "${BLUE}📊 로그 모니터링 종료${NC}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - 모니터링 중단됨"
    exit 0
}

trap cleanup INT TERM

# Cloud Run 로그 스트리밍 (실시간)
gcloud logging tail "resource.type=cloud_run_revision AND resource.labels.service_name=$SERVICE_NAME" \
    --project="$PROJECT_ID" \
    --format="value(timestamp,textPayload,jsonPayload.message)" \
    2>/dev/null | format_log

# 만약 위 명령이 실패하면 대체 방법 시도
if [ $? -ne 0 ]; then
    echo -e "${YELLOW}⚠️  실시간 스트리밍에 실패했습니다. 최근 로그를 표시합니다.${NC}"
    
    gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=$SERVICE_NAME" \
        --project="$PROJECT_ID" \
        --limit=50 \
        --format="value(timestamp,textPayload,jsonPayload.message)" \
        --freshness=1h \
        2>/dev/null | format_log
fi