# 🚀 UniBuy Cloud Deployment Guide

This guide will walk you through hosting your entire UniBuy app on the cloud for free, so your teacher can test it!

## Part 1: Host the Database & Backend (Option: Render.com)

Render is the absolute easiest system for Node.js apps.

1. **Create an account** at [Render.com](https://render.com).
2. **Setup PostgreSQL Database:**
   - Click **New +** -> **PostgreSQL**.
   - Name it `unibuy-db`. Click **Create**.
   - Once created, scroll down to connections and copy the **Internal Database URL** (e.g. `postgres://user:pass@host/db`).
3. **Deploy the Node.js Backend:**
   - First, put your code on a GitHub repository. (Make sure you `.gitignore` your `node_modules` and `.env`).
   - On Render, click **New +** -> **Web Service**.
   - Connect your GitHub repo.
   - For **Root Directory**, type: `backend`
   - For **Build Command**, type: `npm install`
   - For **Start Command**, type: `npm start`
   - **Environment Variables:** Add `DATABASE_URL` and paste the postgres URL you copied earlier. (Also add `FIREBASE_SERVICE_ACCOUNT` if you want Admin SDK).
   - Click **Create Web Service**. 
4. **Copy your Backend URL:** Once deployed, Render will give you a URL like `https://unibuy-backend-xyz.onrender.com`.

## Part 2: Connect the Flutter App

I have simplified your code! You no longer need to hunt down URLs.

1. Open `lib/config.dart`.
2. Change `isProduction` to `true`.
3. Paste your Render URL into `productionBackendUrl` (e.g. `https://unibuy-backend-xyz.onrender.com`).

## Part 3: Host the Flutter App (Option: Firebase Hosting)

Since you already use Firebase for Authentication, Firebase Hosting is the easiest!

1. Open your terminal in the root `UniBuy` folder (not backend).
2. Run this command to build the web app:
   ```powershell
   flutter build web
   ```
3. Initialize Firebase Hosting:
   ```powershell
   firebase init hosting
   ```
   - Select your existing UniBuy Firebase project.
   - When it asks for your public directory, type: `build/web`
   - Configure as a single-page app? Type: `y`
   - Overwrite index.html? Type: `N`
4. Deploy to the world!
   ```powershell
   firebase deploy --only hosting
   ```

**That's it! Firebase will give you a `.web.app` URL that you can send directly to your teacher to test on any device!**
