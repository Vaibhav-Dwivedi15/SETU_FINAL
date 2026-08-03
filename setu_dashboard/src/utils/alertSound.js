// Short synthesized beep for new critical/high alerts — uses the Web
// Audio API directly instead of shipping an audio file, so there's
// nothing extra to load or host. Two quick tones for "critical", one
// for anything else, roughly mirroring how real alarm systems escalate.
let audioCtx = null;

function getAudioContext() {
  if (!audioCtx) {
    const AudioContextClass = window.AudioContext || window.webkitAudioContext;
    if (!AudioContextClass) return null;
    audioCtx = new AudioContextClass();
  }
  return audioCtx;
}

function beep(ctx, startTime, frequency = 880, duration = 0.15) {
  const oscillator = ctx.createOscillator();
  const gain = ctx.createGain();
  oscillator.type = "sine";
  oscillator.frequency.value = frequency;
  gain.gain.setValueAtTime(0.001, startTime);
  gain.gain.exponentialRampToValueAtTime(0.15, startTime + 0.01);
  gain.gain.exponentialRampToValueAtTime(0.001, startTime + duration);
  oscillator.connect(gain);
  gain.connect(ctx.destination);
  oscillator.start(startTime);
  oscillator.stop(startTime + duration);
}

export function playAlertSound(priority = "Medium") {
  const ctx = getAudioContext();
  if (!ctx) return; // Web Audio unsupported — fail silently, this is a nice-to-have
  const now = ctx.currentTime;

  if (priority === "Critical") {
    beep(ctx, now, 1046, 0.12);
    beep(ctx, now + 0.16, 1046, 0.12);
  } else {
    beep(ctx, now, 784, 0.14);
  }
}
