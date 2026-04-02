@echo off
echo ==========================================
echo Fabio — Setup Initial Users
echo ==========================================
echo.

cd backend
echo Installing/Checking Dependencies (bcrypt, passlib)...
..\\.venv\\Scripts\\pip install -r requirements.txt

echo.
echo Seeding Admin User...
..\\.venv\\Scripts\\python seed_admin.py

echo.
echo Setup Complete.
pause
