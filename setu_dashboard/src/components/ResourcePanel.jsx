function ResourcePanel() {
  return (
    <div className="resource-panel">
      <h2>🚑 Emergency Resources</h2>

      <div className="resource-card">
        <h3>🚑 Ambulances</h3>
        <h1>24</h1>
      </div>

      <div className="resource-card">
        <h3>🚒 Fire Trucks</h3>
        <h1>12</h1>
      </div>

      <div className="resource-card">
        <h3>🚓 Police Units</h3>
        <h1>36</h1>
      </div>

      <div className="resource-card">
        <h3>🚁 Rescue Drones</h3>
        <h1>8</h1>
      </div>
    </div>
  );
}

export default ResourcePanel;