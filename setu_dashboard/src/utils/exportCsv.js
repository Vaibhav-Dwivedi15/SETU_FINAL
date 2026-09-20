// Turns the current (already-filtered) incident list into a downloaded
// CSV file, entirely client-side — no backend endpoint needed for this.
// Genuinely useful for a responder/government user who wants to hand a
// filtered incident list to someone else or archive it outside the app.
export function exportIncidentsToCsv(incidents, filename = "setu-incidents.csv") {
  const headers = ["ID", "Type", "City", "Priority", "Status", "Reported At", "Latitude", "Longitude", "Hop Count", "Merged Reports"];

  const rows = incidents.map((i) => [
    i.id,
    i.type,
    i.city,
    i.priority || "Medium",
    i.status === "closed" ? "Closed" : "Active",
    i.reportedAt ? new Date(i.reportedAt).toISOString() : "",
    i.lat,
    i.lng,
    typeof i.hopCount === "number" ? i.hopCount : "",
    i.reportCount || 1,
  ]);

  // Quote every field and escape embedded quotes — city/type names are
  // free text from the backend and could theoretically contain commas.
  const escapeCell = (value) => `"${String(value ?? "").replace(/"/g, '""')}"`;
  const csvContent = [headers, ...rows]
    .map((row) => row.map(escapeCell).join(","))
    .join("\r\n");

  const blob = new Blob([csvContent], { type: "text/csv;charset=utf-8;" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
}
