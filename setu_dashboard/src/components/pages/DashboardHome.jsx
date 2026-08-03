import StatsCards from "../StatsCards";
import MapView from "../MapView";
import IncidentList from "../IncidentList";
import AnalyticsChart from "../AnalyticsChart";
import AIPanel from "../AIPanel";
import ResourcePanel from "../ResourcePanel";

function DashboardHome({ allIncidents, filteredIncidents, onResolve, onSelectIncident, trends }) {
  return (
    <>
      <StatsCards incidents={allIncidents} trends={trends} />

      <div className="dashboard-grid">
        <div className="map-section">
          <h2>🗺 Live Map</h2>
          <MapView incidents={filteredIncidents} onSelectIncident={onSelectIncident} />
        </div>

        <IncidentList
          incidents={filteredIncidents}
          onResolve={onResolve}
          onSelect={onSelectIncident}
        />
      </div>

      <AnalyticsChart incidents={allIncidents} />
      <AIPanel incidents={allIncidents} />
      <ResourcePanel />
    </>
  );
}

export default DashboardHome;
