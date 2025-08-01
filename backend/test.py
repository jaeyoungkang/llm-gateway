from llm_client import LLMClient

client = LLMClient("https://your-cloudrun-url.run.app")

# 테스트
result = client.chat("파이썬이 뭐야?")
print("응답:", result['response'])

logs = client.get_logs()
print(f"총 로그: {len(logs)}개")