import { useEffect, useState } from "react";
import { fetchResponders } from "../../services/api";
import mockTeams from "../../data/teams";
import { SkeletonGrid } from "../Skeleton";

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
        <p className="teams-source-note">Checking backend responder registry...</p>
        <SkeletonGrid count={4} height={90} />
      </div>
    );
  }

  return (
    <div className="teams-page">
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
              {team.area && <span className="team-card-area">📍 {team.area}</span>}
              {team.status && (
                <span className={`status-badge ${team.status === "On Duty" ? "active" : "closed"}`}>
                  {team.status}
                </span>
              )}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

export default TeamsPage;
