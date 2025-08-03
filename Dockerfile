# 멀티스테이지 빌드 - 빌드 스테이지
FROM python:3.11-slim as builder

# 시스템 패키지 업데이트 및 빌드 도구 설치
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Python 의존성 설치
COPY backend/requirements.txt /tmp/
RUN pip install --user --no-cache-dir -r /tmp/requirements.txt

# 프로덕션 스테이지
FROM python:3.11-slim

# 보안을 위한 non-root 사용자 생성
RUN groupadd -r appuser && useradd -r -g appuser appuser

# 작업 디렉토리 생성 및 권한 설정
WORKDIR /app
RUN chown appuser:appuser /app

# 빌드 스테이지에서 설치된 패키지 복사
COPY --from=builder /root/.local /home/appuser/.local

# PATH에 사용자 로컬 bin 추가
ENV PATH=/home/appuser/.local/bin:$PATH

# 애플리케이션 파일 복사
COPY --chown=appuser:appuser backend/ .

# 로그 디렉토리 생성 (권한 설정)
RUN mkdir -p /app/logs && chown appuser:appuser /app/logs

# 비루트 사용자로 전환
USER appuser

# 환경 변수 설정
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV FLASK_ENV=production

# 포트 설정 (Cloud Run 호환)
ENV PORT=8080
EXPOSE $PORT

# 헬스체크 설정
HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \
    CMD python -c "import requests; requests.get('http://localhost:$PORT/health', timeout=10)"

# Gunicorn으로 프로덕션 서버 실행
CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 0 app:app