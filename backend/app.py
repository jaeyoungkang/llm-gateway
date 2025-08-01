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

load_dotenv('.env.local')
ANTHROPIC_API_KEY = os.getenv('ANTHROPIC_API_KEY')
if not ANTHROPIC_API_KEY:
    print("경고: ANTHROPIC_API_KEY 환경 변수가 설정되지 않았습니다.")

# 로깅 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
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

# DB 초기화 (앱 시작시 한번만)
conn = sqlite3.connect('logs.db')
conn.execute('CREATE TABLE IF NOT EXISTS logs (id TEXT, input TEXT, output TEXT, created_at TEXT)')
conn.close()

@app.route('/chat', methods=['POST'])
def chat():
    data = request.json
    
    # Claude 호출
    response = claude.messages.create(
        model="claude-3-5-sonnet-20241022",
        max_tokens=1000,
        messages=[{"role": "user", "content": data['message']}]
    )
    
    result = response.content[0].text
    
    # 로그 저장
    log_id = str(uuid.uuid4())[:8]
    conn = sqlite3.connect('logs.db')
    conn.execute('INSERT INTO logs VALUES (?, ?, ?, ?)', 
                (log_id, data['message'], result, datetime.now().isoformat()))
    conn.commit()
    conn.close()
    
    return jsonify({'response': result, 'id': log_id})

@app.route('/logs')
def get_logs():
    conn = sqlite3.connect('logs.db')
    logs = conn.execute('SELECT * FROM logs ORDER BY created_at DESC LIMIT 20').fetchall()
    conn.close()
    
    return jsonify([{'id': row[0], 'input': row[1], 'output': row[2], 'time': row[3]} for row in logs])

@app.route('/')
def dashboard():
    return render_template('dashboard.html')

if __name__ == '__main__':
    app.run(debug=True, port=8000)