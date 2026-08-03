export function SkeletonCard({ height = 90 }) {
  return <div className="skeleton-card" style={{ height }} />;
}

export function SkeletonGrid({ count = 4, height = 90 }) {
  return (
    <div className="teams-grid">
      {Array.from({ length: count }).map((_, i) => (
        <SkeletonCard key={i} height={height} />
      ))}
    </div>
  );
}
