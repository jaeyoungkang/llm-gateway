from flask import Flask, request, jsonify, render_template
from flask_cors import CORS
import anthropic
import sqlite3
import uuid
from datetime import datetime
import os
import logging
from dotenv import load_dotenv

app = Flask(__name__)
CORS(app)

# 환경별 설정 로드
if os.path.exists('.env.local'):
    load_dotenv('.env.local')
else:
    # 프로덕션 환경에서는 환경 변수 직접 사용
    pass

ANTHROPIC_API_KEY = os.getenv('ANTHROPIC_API_KEY')
if not ANTHROPIC_API_KEY:
    print("경고: ANTHROPIC_API_KEY 환경 변수가 설정되지 않았습니다.")

# 로깅 설정 (Cloud Logging 호환)
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler()  # stdout으로 출력 (Cloud Logging에서 수집)
    ]
)
logger = logging.getLogger(__name__)

def initialize_anthropic_client():
    """Anthropic 클라이언트 초기화"""
    try:
        if not ANTHROPIC_API_KEY:
            logger.warning("Anthropic API 키가 설정되지 않았습니다.")
            return None
        client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)
        logger.info("Anthropic 클라이언트가 성공적으로 초기화되었습니다.")
        return client
    except Exception as e:
        logger.error(f"Anthropic 클라이언트 초기화 실패: {e}")
        return None

claude = initialize_anthropic_client()

def init_db():
    """데이터베이스 초기화"""
    try:
        conn = sqlite3.connect('logs.db', timeout=30)
        conn.execute('''CREATE TABLE IF NOT EXISTS logs 
                       (id TEXT PRIMARY KEY, input TEXT, output TEXT, created_at TEXT)''')
        conn.commit()
        conn.close()
        logger.info("데이터베이스 초기화 완료")
    except Exception as e:
        logger.error(f"데이터베이스 초기화 실패: {e}")

# 앱 시작시 DB 초기화
init_db()

@app.route('/health')
def health_check():
    """헬스체크 엔드포인트 (Cloud Run 필수)"""
    try:
        # 간단한 DB 연결 테스트
        conn = sqlite3.connect('logs.db', timeout=5)
        conn.execute('SELECT 1')
        conn.close()
        
        return jsonify({
            'status': 'healthy',
            'timestamp': datetime.now().isoformat(),
            'service': 'llm-gateway'
        }), 200
    except Exception as e:
        logger.error(f"헬스체크 실패: {e}")
        return jsonify({
            'status': 'unhealthy',
            'error': str(e),
            'timestamp': datetime.now().isoformat()
        }), 503

@app.route('/chat', methods=['POST'])
def chat():
    try:
        if not claude:
            return jsonify({'error': 'Anthropic 클라이언트가 초기화되지 않았습니다.'}), 500
            
        data = request.json
        if not data or 'message' not in data:
            return jsonify({'error': '메시지가 필요합니다.'}), 400
        
        # Claude 호출
        response = claude.messages.create(
            model="claude-3-5-sonnet-20241022",
            max_tokens=1000,
            messages=[{"role": "user", "content": data['message']}]
        )
        
        result = response.content[0].text
        
        # 로그 저장
        log_id = str(uuid.uuid4())[:8]
        try:
            conn = sqlite3.connect('logs.db', timeout=30)
            conn.execute('INSERT INTO logs VALUES (?, ?, ?, ?)', 
                        (log_id, data['message'], result, datetime.now().isoformat()))
            conn.commit()
            conn.close()
        except Exception as db_error:
            logger.warning(f"로그 저장 실패: {db_error}")
        
        return jsonify({'response': result, 'id': log_id})
        
    except Exception as e:
        logger.error(f"채팅 처리 중 오류: {e}")
        return jsonify({'error': '서버 오류가 발생했습니다.'}), 500

@app.route('/logs')
def get_logs():
    try:
        conn = sqlite3.connect('logs.db', timeout=30)
        logs = conn.execute('SELECT * FROM logs ORDER BY created_at DESC LIMIT 20').fetchall()
        conn.close()
        
        return jsonify([{'id': row[0], 'input': row[1], 'output': row[2], 'time': row[3]} for row in logs])
        
    except Exception as e:
        logger.error(f"로그 조회 중 오류: {e}")
        return jsonify({'error': '로그를 불러올 수 없습니다.'}), 500

@app.route('/')
def dashboard():
    return render_template('dashboard.html')

if __name__ == '__main__':
    # 로컬 개발 환경
    app.run(debug=True, host='0.0.0.0', port=int(os.environ.get('PORT', 8000)))
else:
    # 프로덕션 환경 (Gunicorn에서 실행)
    logger.info("프로덕션 모드로 시작됨")