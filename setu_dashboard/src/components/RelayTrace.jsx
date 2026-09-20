// =====================================================
// SETU Dashboard
// Component : Relay Trace
// =====================================================
//
// Added Aug 6 2026. Replaces a generic "live" pulse dot with something
// that encodes real system truth unique to SETU: hopCount is the
// actual number of relay devices this packet passed through before
// reaching a device with internet -- a real BLE/Wi-Fi Direct mesh
// journey, not a decorative animation. Each node in the chain is one
// hop; the final lit node is where the packet reached connectivity.
//
// hopCount === 0 means the origin device had internet directly (no
// relay needed) -- rendered as a single lit node with no chain, so a
// direct-to-backend report doesn't visually claim a mesh journey it
// didn't take.

function RelayTrace({ hopCount }) {
  if (typeof hopCount !== "number") return null;

  if (hopCount === 0) {
    return (
      <div className="relay-trace relay-trace-direct" title="Reported directly — no mesh relay needed">
        <span className="relay-node relay-node-lit" />
        <span className="relay-trace-label mono">direct</span>
      </div>
    );
  }

  // hopCount + 1 nodes: origin device, then one node per relay hop.
  const nodeCount = hopCount + 1;
  const nodes = Array.from({ length: nodeCount });

  return (
    <div
      className="relay-trace"
      title={`Relayed through ${hopCount} device${hopCount === 1 ? "" : "s"} before reaching connectivity`}
    >
      {nodes.map((_, i) => (
        <span key={i} className="relay-trace-segment">
          <span className="relay-node relay-node-lit" />
          {i < nodes.length - 1 && <span className="relay-link" />}
        </span>
      ))}
      <span className="relay-trace-label mono">{hopCount} hop{hopCount === 1 ? "" : "s"}</span>
    </div>
  );
}

export default RelayTrace;
