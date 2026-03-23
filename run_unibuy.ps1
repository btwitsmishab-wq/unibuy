# Run script for UniBuy
Write-Host "Starting UniBuy Project..." -ForegroundColor Cyan

# 1. Start Backend in a new window
Write-Host ">>> Starting Backend (Port 5000)..." -ForegroundColor Green
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd backend; npm install; npm start"

# 2. Wait a moment for backend to initialize
Start-Sleep -Seconds 2

# 3. Start Frontend (Flutter)
Write-Host ">>> Starting Frontend (Flutter)..." -ForegroundColor Yellow
flutter pub get
flutter run
