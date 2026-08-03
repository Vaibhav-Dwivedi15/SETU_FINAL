import { MapContainer, TileLayer, Marker, Popup } from "react-leaflet";
import "leaflet/dist/leaflet.css";
import { Icon } from "leaflet";
import { useTheme } from "../context/ThemeContext";

// Icons are keyed by URGENCY, not incident type — matches the role brief
// ("markers ... color-coded by urgency"). Previously these were keyed by
// type (Fire=red, Flood=blue, Medical=green), which was a deviation from
// spec: a Low-priority Fire and a Critical Fire looked identical.
const redIcon = new Icon({
  iconUrl: "https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-red.png",
  shadowUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png",
  iconSize: [25, 41],
  iconAnchor: [12, 41],
});

const orangeIcon = new Icon({
  iconUrl: "https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-orange.png",
  shadowUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png",
  iconSize: [25, 41],
  iconAnchor: [12, 41],
});

const goldIcon = new Icon({
  iconUrl: "https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-gold.png",
  shadowUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png",
  iconSize: [25, 41],
  iconAnchor: [12, 41],
});

const greenIcon = new Icon({
  iconUrl: "https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-green.png",
  shadowUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png",
  iconSize: [25, 41],
  iconAnchor: [12, 41],
});

const greyIcon = new Icon({
  iconUrl: "https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-grey.png",
  shadowUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png",
  iconSize: [25, 41],
  iconAnchor: [12, 41],
});

function getMarker(priority) {
  switch (priority) {
    case "Critical":
      return redIcon;
    case "High":
      return orangeIcon;
    case "Medium":
      return goldIcon;
    case "Low":
      return greenIcon;
    default:
      return greyIcon;
  }
}

function MapView({ incidents, onSelectIncident, tall = false }) {
  const { theme } = useTheme();
  const tileUrl = theme === "light"
    ? "https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png"
    : "https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png";

  return (
    <div className={`map-container ${tall ? "map-container-tall" : ""}`}>
      <MapContainer
        center={[25.4358, 81.8463]}
        zoom={6}
        style={{ height: tall ? "100%" : "400px", width: "100%" }}
        scrollWheelZoom
      >
        {/* CARTO dark_all/light_all — free, no API key, switches with the
            dashboard's theme toggle so the map never clashes with the
            surrounding UI in either mode. */}
        <TileLayer
          attribution='&copy; OpenStreetMap, &copy; CARTO'
          url={tileUrl}
        />

        {incidents.map((incident) => (
          <Marker
            key={incident.id}
            position={[incident.lat, incident.lng]}
            icon={getMarker(incident.priority)}
            eventHandlers={
              onSelectIncident ? { click: () => onSelectIncident(incident) } : undefined
            }
          >
            <Popup>
              <strong>{incident.type}</strong>
              <br />
              {incident.city}
              <br />
              {incident.priority}
              <br />
              {/* hop_count is a real field on the frozen packet spec (Section 3).
                  Only renders when it's a number so this stays silent until the
                  backend actually starts sending it — see services/api.js. */}
              {typeof incident.hopCount === "number" && (
                <>
                  🔀 {incident.hopCount} hop{incident.hopCount === 1 ? "" : "s"} — no internet needed
                  <br />
                </>
              )}
              <span style={{ color: incident.status === "closed" ? "#2FA85C" : "#E14545" }}>
                {incident.status === "closed" ? "● Resolved" : "● Active"}
              </span>
            </Popup>
          </Marker>
        ))}
      </MapContainer>

      <div className="map-legend">
        <span><i className="dot dot-critical" /> Critical</span>
        <span><i className="dot dot-high" /> High</span>
        <span><i className="dot dot-medium" /> Medium</span>
        <span><i className="dot dot-low" /> Low</span>
      </div>
    </div>
  );
}

export default MapView;
