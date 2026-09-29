import math
from typing import Dict, Any, List

def calculate_haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate the great circle distance in kilometers between two points on the earth."""
    R = 6371.0 # Earth radius in kilometers

    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)

    a = math.sin(delta_phi / 2)**2 + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

    distance = R * c
    return distance

def point_in_polygon(x: float, y: float, polygon: List[List[float]]) -> bool:
    """
    Ray-casting algorithm to determine if a point (x, y) is inside a polygon.
    polygon is a list of [lon, lat] coordinates (GeoJSON standard).
    x is longitude, y is latitude.
    """
    n = len(polygon)
    inside = False

    p1x, p1y = polygon[0]
    for i in range(n + 1):
        p2x, p2y = polygon[i % n]
        if y > min(p1y, p2y):
            if y <= max(p1y, p2y):
                if x <= max(p1x, p2x):
                    if p1y != p2y:
                        xints = (y - p1y) * (p2x - p1x) / (p2y - p1y) + p1x
                    if p1x == p2x or x <= xints:
                        inside = not inside
        p1x, p1y = p2x, p2y

    return inside

def is_point_in_geojson_polygon(lat: float, lon: float, geojson_geom: Dict[str, Any]) -> bool:
    """
    Determine if a (lat, lon) point is inside a GeoJSON geometry (Polygon or MultiPolygon).
    """
    if not geojson_geom or "type" not in geojson_geom or "coordinates" not in geojson_geom:
        return False
        
    geom_type = geojson_geom["type"]
    coords = geojson_geom["coordinates"]
    
    if geom_type == "Polygon":
        # Check against the exterior ring (index 0)
        return point_in_polygon(lon, lat, coords[0])
    elif geom_type == "MultiPolygon":
        for poly in coords:
            if point_in_polygon(lon, lat, poly[0]):
                return True
    return False

def get_bounding_box(geojson_geom: Dict[str, Any]):
    """
    Returns (min_lat, max_lat, min_lon, max_lon) for a GeoJSON geometry.
    """
    lats = []
    lons = []
    
    def extract_coords(coords_list):
        for item in coords_list:
            if isinstance(item[0], (int, float)):
                lons.append(item[0])
                lats.append(item[1])
            else:
                extract_coords(item)
                
    if not geojson_geom or "coordinates" not in geojson_geom:
        return 0, 0, 0, 0
        
    extract_coords(geojson_geom["coordinates"])
    
    if not lats or not lons:
        return 0, 0, 0, 0
        
    return min(lats), max(lats), min(lons), max(lons)
