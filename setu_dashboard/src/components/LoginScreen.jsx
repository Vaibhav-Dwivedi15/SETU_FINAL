import { useState } from "react";
import { loginWithKey } from "../services/api";
import { CONFIG_ERROR } from "../config";
import "./security.css";

// Responder sign-in (Block 3). The responder key is typed by a human and exchanged for a
// short-lived session token; it is never part of the JavaScript bundle and is not stored.
function LoginScreen({ onSignedIn }) {
  const [key, setKey] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(CONFIG_ERROR);

  async function submit(e) {
    e.preventDefault();
    if (busy || !key) return;
    setBusy(true);
    setError(null);
    try {
      await loginWithKey(key);
      setKey("");
      onSignedIn();
    } catch (err) {
      setError(err.message || "Sign-in failed.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="login-screen">
      <form className="login-card" onSubmit={submit} autoComplete="off">
        <h1>SETU Responder Dashboard</h1>
        <p className="login-help">Sign in with the responder key issued to you. It is exchanged for a temporary session and is not stored in this browser.</p>
        <label htmlFor="responder-key">Responder key</label>
        <input
          id="responder-key"
          type="password"
          value={key}
          onChange={(e) => setKey(e.target.value)}
          autoFocus
          spellCheck={false}
          autoComplete="off"
          disabled={busy || Boolean(CONFIG_ERROR)}
        />
        {error && <p className="login-error" role="alert">{error}</p>}
        <button type="submit" disabled={busy || !key || Boolean(CONFIG_ERROR)}>{busy ? "Signing in…" : "Sign in"}</button>
      </form>
    </main>
  );
}

export default LoginScreen;
