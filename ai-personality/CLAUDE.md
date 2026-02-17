# ai-personality

A web application that combines voice interaction with a 3D animated sphere that responds to AI-generated content and mood.

## Architecture

- **Frontend**: Single-page HTML/JS application
- **3D Rendering**: Three.js for the animated sphere
- **Voice Input**: Web Speech API (SpeechRecognition)
- **AI Inference**: OpenAI Chat Completions API (gpt-4o-mini)
- **Voice Output**: OpenAI TTS API
- **Dev Server**: Simple Node.js HTTP server

## Development

```bash
cd ai-personality
npm install
npm start
```

Set `OPENAI_API_KEY` environment variable before running.

The server runs on port 3000. Open http://localhost:3000 in a browser.

## Key Files

- `server.js` — Express server that proxies OpenAI API calls (keeps API key server-side)
- `public/index.html` — Main application page
- `public/app.js` — Application logic (voice, API calls, sphere animation)
