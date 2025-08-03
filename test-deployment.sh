#!/bin/bash

# Cloud Run 배포 테스트 스크립트
# 사용법: ./test-deployment.sh <SERVICE_URL>

set -e

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 서비스 URL 확인
if [ -z "$1" ]; then
    echo -e "${RED}❌ 사용법: $0 <SERVICE_URL>${NC}"
    echo -e "${YELLOW}예시: $0 https://llm-gateway-abc123.run.app${NC}"
    exit 1
fi

SERVICE_URL="$1"
echo -e "${BLUE}🚀 Cloud Run 서비스 테스트 시작${NC}"
echo -e "${BLUE}📍 서비스 URL: ${SERVICE_URL}${NC}"
echo ""

# 테스트 결과 저장
PASSED=0
FAILED=0

# 테스트 함수
test_endpoint() {
    local name="$1"
    local url="$2"
    local method="$3"
    local data="$4"
    local expected_status="$5"
    
    echo -n "🧪 ${name} 테스트 중... "
    
    if [ "$method" = "POST" ]; then
        response=$(curl -s -w "\n%{http_code}" -X POST \
            -H "Content-Type: application/json" \
            -d "$data" \
            "$url" 2>/dev/null)
    else
        response=$(curl -s -w "\n%{http_code}" "$url" 2>/dev/null)
    fi
    
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" = "$expected_status" ]; then
        echo -e "${GREEN}✅ 성공 (HTTP $http_code)${NC}"
        PASSED=$((PASSED + 1))
        
        # 응답 내용 미리보기 (첫 100자)
        if [ ${#body} -gt 0 ]; then
            preview=$(echo "$body" | head -c 100)
            echo -e "   ${GREEN}└─ 응답: ${preview}...${NC}"
        fi
    else
        echo -e "${RED}❌ 실패 (HTTP $http_code, 예상: $expected_status)${NC}"
        FAILED=$((FAILED + 1))
        
        if [ ${#body} -gt 0 ]; then
            echo -e "   ${RED}└─ 오류: $body${NC}"
        fi
    fi
    echo ""
}

# 1. 헬스체크 테스트
test_endpoint "헬스체크" "${SERVICE_URL}/health" "GET" "" "200"

# 2. 대시보드 테스트
test_endpoint "대시보드" "${SERVICE_URL}/" "GET" "" "200"

# 3. 로그 조회 테스트
test_endpoint "로그 조회" "${SERVICE_URL}/logs" "GET" "" "200"

# 4. 채팅 API 테스트 (ANTHROPIC_API_KEY가 설정된 경우에만)
echo -n "🤖 채팅 API 테스트 중... "
chat_response=$(curl -s -w "\n%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d '{"message":"안녕하세요! 간단한 테스트입니다."}' \
    "${SERVICE_URL}/chat" 2>/dev/null)

chat_http_code=$(echo "$chat_response" | tail -n1)
chat_body=$(echo "$chat_response" | sed '$d')

if [ "$chat_http_code" = "200" ]; then
    echo -e "${GREEN}✅ 성공 (HTTP $chat_http_code)${NC}"
    PASSED=$((PASSED + 1))
    
    # JSON에서 response 필드 추출 시도
    if command -v jq >/dev/null 2>&1; then
        response_text=$(echo "$chat_body" | jq -r '.response // empty' 2>/dev/null)
        if [ -n "$response_text" ]; then
            preview=$(echo "$response_text" | head -c 50)
            echo -e "   ${GREEN}└─ Claude 응답: ${preview}...${NC}"
        fi
    else
        preview=$(echo "$chat_body" | head -c 100)
        echo -e "   ${GREEN}└─ 응답: ${preview}...${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  API 키 미설정 또는 오류 (HTTP $chat_http_code)${NC}"
    if [ ${#chat_body} -gt 0 ]; then
        echo -e "   ${YELLOW}└─ 메시지: $chat_body${NC}"
    fi
    # 채팅 API는 실패로 카운트하지 않음 (API 키 의존적)
fi

echo ""
echo -e "${BLUE}📊 테스트 결과 요약${NC}"
echo -e "✅ 성공: ${GREEN}$PASSED${NC}"
echo -e "❌ 실패: ${RED}$FAILED${NC}"

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}🎉 모든 기본 테스트가 성공했습니다!${NC}"
    echo -e "${GREEN}🌐 서비스가 정상적으로 배포되었습니다.${NC}"
    exit 0
else
    echo -e "${RED}💥 일부 테스트가 실패했습니다. 로그를 확인해주세요.${NC}"
    exit 1