// Converts a Date/timestamp into "just now" / "5m ago" / "3h ago" style
// text. No dependency needed for something this small. Falls back to the
// original locale time string once something is over a day old, since
// "23h ago" stops being more useful than an actual time at that point.
export function timeAgo(date) {
  if (!date) return "";
  const then = date instanceof Date ? date : new Date(date);
  if (Number.isNaN(then.getTime())) return "";

  const seconds = Math.floor((Date.now() - then.getTime()) / 1000);

  if (seconds < 5) return "just now";
  if (seconds < 60) return `${seconds}s ago`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  return then.toLocaleTimeString();
}
