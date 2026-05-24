# Chatly Development & Setup Guide 🚀

Follow these steps to run and test the complete Chatly stack locally on your computer.

---

## 📋 Prerequisites

Before starting, ensure you have the following installed:
- **Node.js** (v18 or higher) & **npm**
- **Python** (v3.10 or higher) & **pip**
- **Flutter SDK** (Optional, required for compiling/running client apps locally)

---

## 📱 1. Client App Setup (`apps/mobile`)

The mobile client is a Flutter application. To run it, follow these steps:

1. **Navigate to the app directory**:
   ```bash
   cd apps/mobile
   ```

2. **Fetch Dart packages**:
   ```bash
   flutter pub get
   ```

3. **Recreate platform wrappers**:
   Since the codebase does not check in bulky Gradle/Xcode configurations, let Flutter recreate them dynamically for your current OS target:
   ```bash
   # Recreate all platforms (Android, iOS, Web, Windows, macOS, Linux)
   flutter create --platforms=android,ios,web,windows,macos,linux .
   ```

4. **Launch the application**:
   Make sure you have an active emulator open or target selected, then run:
   ```bash
   flutter run
   ```

---

## 🖥️ 2. Fastify Backend Server Setup (`packages/chatly-server`)

The backend is written in Node.js with TypeScript and Fastify.

1. **Navigate to the server directory**:
   ```bash
   cd packages/chatly-server
   ```

2. **Install dependencies**:
   ```bash
   npm install
   ```

3. **Set up configurations**:
   A template `.env` file is provided. Edit it if you wish to hook up actual PostgreSQL (Supabase) or Redis (Upstash) credentials:
   ```bash
   # If left commented, the server will boot automatically using an In-Memory cache fallback.
   ```

4. **Run the server in development mode** (automatic watch reload):
   ```bash
   npm run dev
   ```

5. **Build and start production code**:
   ```bash
   npm run build
   npm start
   ```

---

## 🤖 3. Python ML Service Setup (`packages/chatly-ml`)

The moderation service runs a FastAPI endpoint analyzing text content.

1. **Navigate to the service directory**:
   ```bash
   cd packages/chatly-ml
   ```

2. **Install modules**:
   ```bash
   pip install -r requirements.txt
   ```

3. **Boot the service**:
   ```bash
   python app.py
   # The endpoint will start running at http://localhost:8000
   # If torch/detoxify BERT downloads fail or are absent, it falls back to keyword filters automatically.
   ```
