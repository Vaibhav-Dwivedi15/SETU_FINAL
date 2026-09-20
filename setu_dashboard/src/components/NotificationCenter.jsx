import { useEffect, useRef, useState } from "react";
import { timeAgo } from "../utils/timeAgo";
import { useTick } from "../utils/useTick";
import { ActionIcons } from "../icons";

function NotificationCenter({ notifications, onMarkAllRead, onClear, onSelect }) {
  const [open, setOpen] = useState(false);
  const panelRef = useRef(null);
  useTick(30000);

  const unreadCount = notifications.filter((n) => !n.read).length;

  useEffect(() => {
    function handleClickOutside(e) {
      if (panelRef.current && !panelRef.current.contains(e.target)) setOpen(false);
    }
    if (open) document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, [open]);

  function toggle() {
    const next = !open;
    setOpen(next);
    if (next && unreadCount > 0) onMarkAllRead();
  }

  return (
    <div className="notif-center" ref={panelRef}>
      <button className="notif-bell" onClick={toggle} aria-label="Notifications">
        <ActionIcons.notifications className="ds-icon-md" aria-hidden="true" />
        {unreadCount > 0 && <span className="notif-badge">{unreadCount > 9 ? "9+" : unreadCount}</span>}
      </button>

      {open && (
        <div className="notif-panel">
          <div className="notif-panel-header">
            <h4>Notifications</h4>
            {notifications.length > 0 && (
              <button className="notif-clear-btn" onClick={onClear}>Clear all</button>
            )}
          </div>

          {notifications.length === 0 && (
            <div className="notif-empty">No notifications yet.</div>
          )}

          <div className="notif-list">
            {notifications.map((n) => (
              <div
                key={n.id}
                className={`notif-item ${n.incident ? "notif-item-clickable" : ""}`}
                onClick={() => n.incident && onSelect(n.incident)}
              >
                <span className={`rail-dot dot-${(n.priority || "medium").toLowerCase()}`} />
                <div className="notif-item-body">
                  <strong>{n.type} — {n.city}</strong>
                  <span className="mono">{timeAgo(n.at)}</span>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

export default NotificationCenter;
