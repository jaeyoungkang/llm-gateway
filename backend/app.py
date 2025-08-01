from flask import Flask, request, jsonify, render_template
from flask_cors import CORS
from anthropic import Anthropic
import sqlite3
import uuid
from datetime import datetime
import os

app = Flask(__name__)
CORS(app)

claude = Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY", "your-key-here"))

# DB 초기화 (앱 시작시 한번만)
conn = sqlite3.connect('logs.db')
conn.execute('CREATE TABLE IF NOT EXISTS logs (id TEXT, input TEXT, output TEXT, created_at TEXT)')
conn.close()

@app.route('/chat', methods=['POST'])
def chat():
    data = request.json
    
    # Claude 호출
    response = claude.messages.create(
        model="claude-3-sonnet-20240229",
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