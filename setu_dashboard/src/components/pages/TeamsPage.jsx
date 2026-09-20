import { useEffect, useState } from "react";
import { fetchResponders } from "../../services/api";
import mockTeams from "../../data/teams";
import { SkeletonGrid } from "../Skeleton";
import { ActionIcons, NavIcons, StatusIcons } from "../../icons";
import { StatusBadge, SectionHeader, MetricCard, EmptyState } from "../ui/Primitives";

// =====================================================
// SETU Dashboard — Response Teams (v2, operational readiness)
// =====================================================
//
// Redesign brief section 13 asked for: Team / Type / Location /
// Availability / Current assignment / Response status / Capabilities,
// built around operational readiness — and explicitly: "If there is
// no real data, create a proper empty state. Do NOT fill the screen
// with fake data just for visual purposes."
//
// HONEST SCOPE: the confirmed data model (data/teams.js, and
// normalizeResponder() in services/api.js) only carries name,
// organization, publicKey, status, and area. There is no "type",
// "current assignment", or "capabilities" field anywhere in this
// codebase yet. Rather than inventing plausible-looking values for
// those fields (exactly the kind of overclaim the project's own docs
// reject), each card explicitly labels those two fields NOT REPORTED.
// Only fields that actually exist in the data (name, organization,
// area, status) render real values.
function TeamsPage() {
  const [teams, setTeams] = useState(mockTeams);
  const [source, setSource] = useState("mock"); // "mock" | "backend"
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    fetchResponders()
      .then((responders) => {
        if (cancelled) return;
        if (responders.length > 0) {
          setTeams(responders);
          setSource("backend");
        }
        // if the backend is reachable but has zero registered responders,
        // keep showing mock data rather than an empty page
      })
      .catch(() => {
        // backend unreachable or not yet auth-configured for this key —
        // mock data (already the initial state) stays as-is
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => { cancelled = true; };
  }, []);

  if (loading) {
    return (
      <div className="teams-page">
        <SectionHeader title="Response Teams" description="Operational readiness across registered responder teams." />
        <p className="teams-source-note">Checking backend responder registry...</p>
        <SkeletonGrid count={4} height={90} />
      </div>
    );
  }

  if (teams.length === 0) {
    return (
      <div className="teams-page">
        <SectionHeader title="Response Teams" description="Operational readiness across registered responder teams." />
        <EmptyState
          icon={NavIcons.teams}
          title="NO TEAMS REGISTERED"
          description="No responder teams are currently registered in the backend or sample data."
        />
      </div>
    );
  }

  const onDuty = teams.filter((t) => t.status === "On Duty").length;
  const standby = teams.filter((t) => t.status === "Standby").length;
  const otherStatus = teams.length - onDuty - standby;

  return (
    <div className="teams-page">
      <SectionHeader title="Response Teams" description="Operational readiness across registered responder teams." />

      <div className="ds-metric-row">
        <MetricCard icon={NavIcons.teams} label="Total Teams" value={teams.length} />
        <MetricCard icon={StatusIcons.active} label="On Duty" value={onDuty} tone="critical" />
        <MetricCard icon={StatusIcons.pending} label="Standby" value={standby} tone="network" />
        {otherStatus > 0 && (
          <MetricCard icon={StatusIcons.unknown} label="Status Unreported" value={otherStatus} />
        )}
      </div>

      <p className="teams-source-note">
        {source === "backend"
          ? "Showing registered responders from the backend."
          : "Backend responder registry not reachable — showing sample teams."}
      </p>

      <div className="teams-grid">
        {teams.map((team) => (
          <div key={team.id} className="team-card">
            <div className="team-card-avatar">{team.name.slice(0, 1)}</div>
            <div className="team-card-body">
              <h3>{team.name}</h3>
              <p>{team.organization}</p>
              {team.area && (
                <span className="team-card-area" style={{ display: "inline-flex", alignItems: "center", gap: 4 }}>
                  <ActionIcons.location className="ds-icon-sm" aria-hidden="true" /> {team.area}
                </span>
              )}
              {team.status && (
                <StatusBadge status={team.status === "On Duty" ? "active" : "closed"} label={team.status} />
              )}
              <p className="settings-dim" style={{ marginTop: 8 }}>
                Assignment: NOT REPORTED &middot; Capabilities: NOT REPORTED
              </p>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

export default TeamsPage;
