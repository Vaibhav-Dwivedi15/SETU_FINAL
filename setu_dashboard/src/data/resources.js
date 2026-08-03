// Previously these numbers were hardcoded directly inside
// ResourcePanel's JSX with no way to reuse them elsewhere. Centralizing
// here lets the new full Resources page (a table/detail view) and the
// compact dashboard cards both read from the same data.
const resourcesData = [
  { id: "r1", type: "Ambulance", icon: "🚑", total: 24, deployed: 9, available: 15, base: "Prayagraj Central" },
  { id: "r2", type: "Fire Truck", icon: "🚒", total: 12, deployed: 4, available: 8, base: "Lucknow HQ" },
  { id: "r3", type: "Police Unit", icon: "🚓", total: 36, deployed: 14, available: 22, base: "Varanasi District" },
  { id: "r4", type: "Rescue Drone", icon: "🚁", total: 8, deployed: 2, available: 6, base: "Kanpur Depot" },
];

export default resourcesData;
