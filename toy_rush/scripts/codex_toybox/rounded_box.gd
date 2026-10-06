extends RefCounted
## Render-only replacement. The box bounds, node transform and gameplay stay intact.

static var _cache: Dictionary = {}

static func make(size: Vector3) -> ArrayMesh:
	var key := str(size)
	if _cache.has(key):
		return _cache[key]
	var half := size * 0.5
	var radius := minf(0.14, minf(size.x, minf(size.y, size.z)) * 0.18)
	var core := half - Vector3.ONE * radius
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for axis in 3:
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		var xs := _samples(half[u], radius)
		var ys := _samples(half[v], radius)
		for sign_value in [-1.0, 1.0]:
			for i in xs.size() - 1:
				for j in ys.size() - 1:
					var points: Array[Vector3] = []
					for xy in [Vector2(xs[i], ys[j]), Vector2(xs[i + 1], ys[j]), Vector2(xs[i + 1], ys[j + 1]), Vector2(xs[i], ys[j + 1])]:
						var p := Vector3.ZERO
						p[axis] = half[axis] * sign_value
						p[u] = xy.x
						p[v] = xy.y
						points.append(p)
					# Godot uses clockwise front faces.
					var indices := [0, 2, 1, 0, 3, 2] if sign_value > 0.0 else [0, 1, 2, 0, 2, 3]
					for index in indices:
						var p := points[index]
						var q := p.clamp(-core, core)
						var normal := (p - q).normalized()
						st.set_normal(normal)
						st.set_uv(Vector2((p[u] / half[u] + 1.0) * 0.5, (p[v] / half[v] + 1.0) * 0.5))
						st.add_vertex(q + normal * radius)
	st.index()
	var result := st.commit()
	_cache[key] = result
	return result

static func _samples(half: float, radius: float) -> PackedFloat32Array:
	return PackedFloat32Array([-half, -half + radius * 0.33, -half + radius * 0.67, -half + radius, half - radius, half - radius * 0.67, half - radius * 0.33, half])
