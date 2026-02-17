// ===== Three.js Scene Setup =====
const container = document.getElementById('canvas-container');
const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(60, window.innerWidth / window.innerHeight, 0.1, 100);
camera.position.z = 4;

const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.setPixelRatio(window.devicePixelRatio);
container.appendChild(renderer.domElement);

// Sphere with custom shader for mood-based animation
const vertexShader = `
  uniform float uTime;
  uniform float uDistortion;
  uniform float uSpeed;
  varying vec3 vNormal;
  varying vec3 vPosition;
  varying float vDisplacement;

  // Simplex-like noise
  vec3 mod289(vec3 x) { return x - floor(x * (1.0/289.0)) * 289.0; }
  vec4 mod289(vec4 x) { return x - floor(x * (1.0/289.0)) * 289.0; }
  vec4 permute(vec4 x) { return mod289(((x*34.0)+1.0)*x); }
  vec4 taylorInvSqrt(vec4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

  float snoise(vec3 v) {
    const vec2 C = vec2(1.0/6.0, 1.0/3.0);
    const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);
    vec3 i = floor(v + dot(v, C.yyy));
    vec3 x0 = v - i + dot(i, C.xxx);
    vec3 g = step(x0.yzx, x0.xyz);
    vec3 l = 1.0 - g;
    vec3 i1 = min(g.xyz, l.zxy);
    vec3 i2 = max(g.xyz, l.zxy);
    vec3 x1 = x0 - i1 + C.xxx;
    vec3 x2 = x0 - i2 + C.yyy;
    vec3 x3 = x0 - D.yyy;
    i = mod289(i);
    vec4 p = permute(permute(permute(
      i.z + vec4(0.0, i1.z, i2.z, 1.0))
      + i.y + vec4(0.0, i1.y, i2.y, 1.0))
      + i.x + vec4(0.0, i1.x, i2.x, 1.0));
    float n_ = 0.142857142857;
    vec3 ns = n_ * D.wyz - D.xzx;
    vec4 j = p - 49.0 * floor(p * ns.z * ns.z);
    vec4 x_ = floor(j * ns.z);
    vec4 y_ = floor(j - 7.0 * x_);
    vec4 x = x_ * ns.x + ns.yyyy;
    vec4 y = y_ * ns.x + ns.yyyy;
    vec4 h = 1.0 - abs(x) - abs(y);
    vec4 b0 = vec4(x.xy, y.xy);
    vec4 b1 = vec4(x.zw, y.zw);
    vec4 s0 = floor(b0)*2.0 + 1.0;
    vec4 s1 = floor(b1)*2.0 + 1.0;
    vec4 sh = -step(h, vec4(0.0));
    vec4 a0 = b0.xzyw + s0.xzyw*sh.xxyy;
    vec4 a1 = b1.xzyw + s1.xzyw*sh.zzww;
    vec3 p0 = vec3(a0.xy, h.x);
    vec3 p1 = vec3(a0.zw, h.y);
    vec3 p2 = vec3(a1.xy, h.z);
    vec3 p3 = vec3(a1.zw, h.w);
    vec4 norm = taylorInvSqrt(vec4(dot(p0,p0),dot(p1,p1),dot(p2,p2),dot(p3,p3)));
    p0 *= norm.x; p1 *= norm.y; p2 *= norm.z; p3 *= norm.w;
    vec4 m = max(0.6 - vec4(dot(x0,x0),dot(x1,x1),dot(x2,x2),dot(x3,x3)), 0.0);
    m = m * m;
    return 42.0 * dot(m*m, vec4(dot(p0,x0),dot(p1,x1),dot(p2,x2),dot(p3,x3)));
  }

  void main() {
    vNormal = normal;
    vPosition = position;
    float noise = snoise(position * 2.0 + uTime * uSpeed);
    float displacement = noise * uDistortion;
    vDisplacement = displacement;
    vec3 newPosition = position + normal * displacement;
    gl_Position = projectionMatrix * modelViewMatrix * vec4(newPosition, 1.0);
  }
`;

const fragmentShader = `
  uniform float uTime;
  uniform vec3 uColor1;
  uniform vec3 uColor2;
  uniform float uGlow;
  varying vec3 vNormal;
  varying vec3 vPosition;
  varying float vDisplacement;

  void main() {
    float fresnel = pow(1.0 - abs(dot(vNormal, vec3(0.0, 0.0, 1.0))), 2.0);
    vec3 color = mix(uColor1, uColor2, vDisplacement * 2.0 + 0.5);
    color += fresnel * uGlow * vec3(0.5, 0.7, 1.0);
    float alpha = 0.85 + fresnel * 0.15;
    gl_FragColor = vec4(color, alpha);
  }
`;

const uniforms = {
  uTime: { value: 0 },
  uDistortion: { value: 0.15 },
  uSpeed: { value: 0.3 },
  uColor1: { value: new THREE.Color(0x4a6cf7) },
  uColor2: { value: new THREE.Color(0x8b5cf6) },
  uGlow: { value: 0.5 },
};

const geometry = new THREE.SphereGeometry(1.2, 128, 128);
const material = new THREE.ShaderMaterial({
  vertexShader,
  fragmentShader,
  uniforms,
  transparent: true,
});
const sphere = new THREE.Mesh(geometry, material);
scene.add(sphere);

// Ambient light particles
const particleCount = 200;
const particleGeometry = new THREE.BufferGeometry();
const positions = new Float32Array(particleCount * 3);
for (let i = 0; i < particleCount; i++) {
  positions[i * 3] = (Math.random() - 0.5) * 10;
  positions[i * 3 + 1] = (Math.random() - 0.5) * 10;
  positions[i * 3 + 2] = (Math.random() - 0.5) * 10;
}
particleGeometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));
const particleMaterial = new THREE.PointsMaterial({ color: 0x4a6cf7, size: 0.02, transparent: true, opacity: 0.6 });
const particles = new THREE.Points(particleGeometry, particleMaterial);
scene.add(particles);

// ===== Mood System =====
const moods = {
  neutral:  { color1: [0.29, 0.42, 0.97], color2: [0.55, 0.36, 0.96], distortion: 0.15, speed: 0.3, glow: 0.5 },
  happy:    { color1: [1.0, 0.84, 0.0],   color2: [1.0, 0.55, 0.0],   distortion: 0.25, speed: 0.6, glow: 0.8 },
  excited:  { color1: [1.0, 0.2, 0.4],    color2: [1.0, 0.6, 0.0],    distortion: 0.35, speed: 0.8, glow: 1.0 },
  calm:     { color1: [0.0, 0.8, 0.7],    color2: [0.2, 0.5, 0.9],    distortion: 0.08, speed: 0.15, glow: 0.3 },
  sad:      { color1: [0.2, 0.2, 0.5],    color2: [0.3, 0.15, 0.4],   distortion: 0.05, speed: 0.1, glow: 0.2 },
  thinking: { color1: [0.5, 0.3, 0.9],    color2: [0.3, 0.5, 1.0],    distortion: 0.2, speed: 0.5, glow: 0.6 },
  angry:    { color1: [0.9, 0.1, 0.1],    color2: [0.6, 0.0, 0.0],    distortion: 0.4, speed: 1.0, glow: 0.9 },
};

let targetMood = moods.neutral;
let currentMoodValues = { ...moods.neutral };

function setMood(moodName) {
  const mood = moods[moodName] || moods.neutral;
  targetMood = mood;
}

function lerpValue(current, target, speed) {
  return current + (target - current) * speed;
}

function updateMoodTransition(dt) {
  const speed = 2.0 * dt;
  currentMoodValues.distortion = lerpValue(currentMoodValues.distortion, targetMood.distortion, speed);
  currentMoodValues.speed = lerpValue(currentMoodValues.speed, targetMood.speed, speed);
  currentMoodValues.glow = lerpValue(currentMoodValues.glow, targetMood.glow, speed);
  for (let i = 0; i < 3; i++) {
    currentMoodValues.color1[i] = lerpValue(currentMoodValues.color1[i], targetMood.color1[i], speed);
    currentMoodValues.color2[i] = lerpValue(currentMoodValues.color2[i], targetMood.color2[i], speed);
  }
  uniforms.uDistortion.value = currentMoodValues.distortion;
  uniforms.uSpeed.value = currentMoodValues.speed;
  uniforms.uGlow.value = currentMoodValues.glow;
  uniforms.uColor1.value.setRGB(currentMoodValues.color1[0], currentMoodValues.color1[1], currentMoodValues.color1[2]);
  uniforms.uColor2.value.setRGB(currentMoodValues.color2[0], currentMoodValues.color2[1], currentMoodValues.color2[2]);
}

// ===== Audio Reactivity =====
let audioAnalyser = null;
let audioDataArray = null;

function setupAudioAnalyser(audioElement) {
  try {
    const audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    const source = audioCtx.createMediaElementSource(audioElement);
    audioAnalyser = audioCtx.createAnalyser();
    audioAnalyser.fftSize = 256;
    source.connect(audioAnalyser);
    audioAnalyser.connect(audioCtx.destination);
    audioDataArray = new Uint8Array(audioAnalyser.frequencyBinCount);
  } catch (e) {
    console.warn('Audio analyser setup failed:', e);
  }
}

function getAudioLevel() {
  if (!audioAnalyser || !audioDataArray) return 0;
  audioAnalyser.getByteFrequencyData(audioDataArray);
  let sum = 0;
  for (let i = 0; i < audioDataArray.length; i++) sum += audioDataArray[i];
  return sum / (audioDataArray.length * 255);
}

// ===== Animation Loop =====
let lastTime = 0;
function animate(time) {
  requestAnimationFrame(animate);
  const dt = Math.min((time - lastTime) / 1000, 0.1);
  lastTime = time;

  uniforms.uTime.value = time * 0.001;

  // Audio reactivity: boost distortion when speaking
  const audioLevel = getAudioLevel();
  if (audioLevel > 0.01) {
    uniforms.uDistortion.value += audioLevel * 0.3;
  }

  updateMoodTransition(dt);

  sphere.rotation.y += 0.003;
  sphere.rotation.x += 0.001;
  particles.rotation.y -= 0.0005;

  renderer.render(scene, camera);
}
animate(0);

window.addEventListener('resize', () => {
  camera.aspect = window.innerWidth / window.innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(window.innerWidth, window.innerHeight);
});

// ===== UI Elements =====
const micBtn = document.getElementById('mic-btn');
const textInput = document.getElementById('text-input');
const sendBtn = document.getElementById('send-btn');
const transcriptEl = document.getElementById('transcript');
const responseEl = document.getElementById('response-text');
const statusEl = document.getElementById('status');

// ===== Conversation History =====
const conversationHistory = [
  {
    role: 'system',
    content: `You are a warm, expressive AI personality. You respond conversationally and naturally. At the END of every response, on a new line, include a mood tag in the format [mood:X] where X is one of: neutral, happy, excited, calm, sad, thinking, angry. Choose the mood that best matches the emotional tone of your response. Keep responses concise (2-3 sentences max).`
  }
];

// ===== Speech Recognition =====
let recognition = null;
let isListening = false;

if ('webkitSpeechRecognition' in window || 'SpeechRecognition' in window) {
  const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
  recognition = new SpeechRecognition();
  recognition.continuous = false;
  recognition.interimResults = true;
  recognition.lang = 'en-US';

  recognition.onresult = (event) => {
    let transcript = '';
    for (let i = event.resultIndex; i < event.results.length; i++) {
      transcript += event.results[i][0].transcript;
    }
    transcriptEl.textContent = transcript;
    if (event.results[event.results.length - 1].isFinal) {
      stopListening();
      handleUserInput(transcript);
    }
  };

  recognition.onerror = (event) => {
    console.error('Speech recognition error:', event.error);
    statusEl.textContent = `Speech error: ${event.error}`;
    stopListening();
  };

  recognition.onend = () => {
    if (isListening) stopListening();
  };
}

function startListening() {
  if (!recognition) {
    statusEl.textContent = 'Speech recognition not supported in this browser';
    return;
  }
  isListening = true;
  micBtn.classList.add('listening');
  micBtn.textContent = '🔴 Listening...';
  statusEl.textContent = 'Listening...';
  setMood('thinking');
  recognition.start();
}

function stopListening() {
  isListening = false;
  micBtn.classList.remove('listening');
  micBtn.textContent = '🎤 Speak';
  try { recognition.stop(); } catch (e) {}
}

micBtn.addEventListener('click', () => {
  if (isListening) {
    stopListening();
  } else {
    startListening();
  }
});

// Text input
sendBtn.addEventListener('click', () => {
  const text = textInput.value.trim();
  if (text) {
    transcriptEl.textContent = text;
    textInput.value = '';
    handleUserInput(text);
  }
});

textInput.addEventListener('keydown', (e) => {
  if (e.key === 'Enter') {
    sendBtn.click();
  }
});

// ===== API Interaction =====
async function handleUserInput(text) {
  statusEl.textContent = 'Thinking...';
  setMood('thinking');

  conversationHistory.push({ role: 'user', content: text });

  try {
    const response = await fetch('/api/chat', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        messages: conversationHistory,
        max_tokens: 200,
      }),
    });

    const data = await response.json();
    if (data.error) {
      statusEl.textContent = `Error: ${data.error.message || data.error}`;
      setMood('sad');
      return;
    }

    const fullReply = data.choices[0].message.content;
    conversationHistory.push({ role: 'assistant', content: fullReply });

    // Extract mood tag
    const moodMatch = fullReply.match(/\[mood:(\w+)\]/);
    const mood = moodMatch ? moodMatch[1] : 'neutral';
    const displayText = fullReply.replace(/\[mood:\w+\]/, '').trim();

    responseEl.textContent = displayText;
    setMood(mood);
    statusEl.textContent = `Mood: ${mood}`;

    // Text-to-speech
    await speakText(displayText);
  } catch (err) {
    statusEl.textContent = `Error: ${err.message}`;
    setMood('sad');
  }
}

// ===== Text-to-Speech via OpenAI =====
let currentAudio = null;

async function speakText(text) {
  try {
    statusEl.textContent = 'Speaking...';
    const response = await fetch('/api/tts', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: 'tts-1',
        input: text,
        voice: 'nova',
      }),
    });

    if (!response.ok) {
      // Fall back to browser TTS
      fallbackSpeak(text);
      return;
    }

    const blob = await response.blob();
    const url = URL.createObjectURL(blob);

    if (currentAudio) {
      currentAudio.pause();
      currentAudio = null;
    }

    const audio = new Audio(url);
    currentAudio = audio;

    // Set up audio analyser for the first time
    if (!audioAnalyser) {
      setupAudioAnalyser(audio);
    }

    audio.onended = () => {
      statusEl.textContent = 'Ready';
      URL.revokeObjectURL(url);
    };

    await audio.play();
  } catch (err) {
    console.warn('TTS failed, using browser fallback:', err);
    fallbackSpeak(text);
  }
}

function fallbackSpeak(text) {
  if ('speechSynthesis' in window) {
    const utterance = new SpeechSynthesisUtterance(text);
    utterance.rate = 1.0;
    utterance.pitch = 1.0;
    utterance.onend = () => { statusEl.textContent = 'Ready'; };
    speechSynthesis.speak(utterance);
  }
}
