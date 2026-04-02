import requests
import json

url = "http://localhost:8000/api/auth/register"
payload = {
    "email": "test@example.com",
    "full_name": "Test User",
    "password": "password123",
    "pin": "123456"
}
headers = {
    "Content-Type": "application/json"
}

try:
    response = requests.post(url, data=json.dumps(payload), headers=headers)
    print(f"Status: {response.status_code}")
    print(f"Body: {response.text}")
except Exception as e:
    print(f"Error: {e}")
