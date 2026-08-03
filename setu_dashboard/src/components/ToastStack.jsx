function ToastStack({ toasts, onDismiss }) {
  if (toasts.length === 0) return null;

  return (
    <div className="toast-stack" role="status" aria-live="polite">
      {toasts.map((toast) => (
        <div key={toast.id} className={`toast toast-${(toast.priority || "medium").toLowerCase()}`}>
          <span className="toast-icon">🚨</span>
          <div className="toast-body">
            <strong>New {toast.priority} Alert</strong>
            <p>{toast.type} — {toast.city}</p>
          </div>
          <button className="toast-close" onClick={() => onDismiss(toast.id)} aria-label="Dismiss">✖</button>
        </div>
      ))}
    </div>
  );
}

export default ToastStack;
