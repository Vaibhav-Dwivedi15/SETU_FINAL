import resourcesData from "../../data/resources";

function ResourcesPage() {
  return (
    <div className="resources-page">
      {resourcesData.map((res) => {
        const pctDeployed = Math.round((res.deployed / res.total) * 100);
        return (
          <div key={res.id} className="resource-detail-card">
            <div className="resource-detail-header">
              <span className="resource-detail-icon">{res.icon}</span>
              <div>
                <h3>{res.type}</h3>
                <p className="resource-detail-base">Base: {res.base}</p>
              </div>
              <span className="resource-detail-total">{res.total}</span>
            </div>

            <div className="resource-bar">
              <div className="resource-bar-fill" style={{ width: `${pctDeployed}%` }} />
            </div>

            <div className="resource-detail-stats">
              <span><i className="dot dot-deployed" /> Deployed: {res.deployed}</span>
              <span><i className="dot dot-available" /> Available: {res.available}</span>
            </div>
          </div>
        );
      })}
    </div>
  );
}

export default ResourcesPage;
