#+private
package collision

Penetration :: struct {
	depth:        f64,
	normal, a, b: [3]f64,
}

EPA_MAX_VERTICES :: 64
EPA_MAX_FACES :: 128
EPA_MAX_EDGES :: 64

EPA_Face :: struct {
	vertices: [3]int,
	normal:   [3]f64,
	distance: f64,
	alive:    bool,
}

EPA :: struct {
	vertices:     [EPA_MAX_VERTICES]Support_Point,
	faces:        [EPA_MAX_FACES]EPA_Face,
	vertex_count: int,
	interior:     [3]f64,
}

// EPA grows a polytope inside A - B until its face nearest the origin reaches
// the surface. That face's normal points from A to B, and its distance is how
// far apart the cores need to move.
penetration_depth :: proc(a, b: Convex, simplex: Simplex, tolerance: f64) -> (Penetration, bool) {
	epa: EPA
	for i in 0 ..< simplex.count {
		epa.vertices[i] = simplex.points[i]
	}
	epa.vertex_count = simplex.count
	if !complete_tetrahedron(a, b, &epa, tolerance) {
		return {}, false
	}

	for vertex in epa.vertices[:4] {
		epa.interior += vertex.point * 0.25
	}
	tetrahedron := [4][3]int{{0, 1, 2}, {0, 3, 1}, {0, 2, 3}, {1, 3, 2}}
	for corners in tetrahedron {
		if !epa_add_face(&epa, corners) {
			return {}, false
		}
	}

	best := -1
	for _ in 0 ..< EPA_MAX_VERTICES {
		best = epa_closest_face(&epa)
		if best == -1 {
			return {}, false
		}
		face := epa.faces[best]
		next := minkowski_support(a, b, face.normal)
		if dot64(next.point, face.normal) - face.distance <= tolerance ||
		   epa.vertex_count == EPA_MAX_VERTICES {
			break
		}

		if !epa_expand(&epa, next) {
			break
		}
	}
	return epa_witness(&epa, best), true
}

// Points and segments have no volume, so they can't enclose the origin. This
// fails for them and the caller uses a fallback normal.
complete_tetrahedron :: proc(a, b: Convex, epa: ^EPA, tolerance: f64) -> bool {
	axes := [3][3]f64{{1, 0, 0}, {0, 1, 0}, {0, 0, 1}}
	if epa.vertex_count == 1 {
		for axis in axes {
			for sign in ([2]f64{1, -1}) {
				candidate := minkowski_support(a, b, axis * sign)
				if epa_try_add(epa, candidate, tolerance) {
					break
				}
			}
			if epa.vertex_count == 2 {
				break
			}
		}
		if epa.vertex_count < 2 {
			return false
		}
	}

	if epa.vertex_count == 2 {
		edge := epa.vertices[1].point - epa.vertices[0].point
		least := 0
		for i in 1 ..< 3 {
			if abs(edge[i]) < abs(edge[least]) {
				least = i
			}
		}
		perpendicular := cross64(edge, axes[least])
		other := cross64(edge, perpendicular)
		for direction in ([4][3]f64{perpendicular, -perpendicular, other, -other}) {
			candidate := minkowski_support(a, b, direction)
			if epa_try_add(epa, candidate, tolerance) {
				break
			}
		}
		if epa.vertex_count < 3 {
			return false
		}
	}

	if epa.vertex_count == 3 {
		normal := cross64(
			epa.vertices[1].point - epa.vertices[0].point,
			epa.vertices[2].point - epa.vertices[0].point,
		)
		for direction in ([2][3]f64{normal, -normal}) {
			candidate := minkowski_support(a, b, direction)
			if epa_try_add(epa, candidate, tolerance) {
				break
			}
		}
	}
	return epa.vertex_count == 4
}

epa_try_add :: proc(epa: ^EPA, candidate: Support_Point, tolerance: f64) -> bool {
	points := epa.vertices[:epa.vertex_count]
	base := points[0].point
	independent := true
	switch len(points) {
	case 1:
		independent = length64(candidate.point - base) > tolerance
	case 2:
		edge := points[1].point - base
		area := cross64(edge, candidate.point - base)
		independent = length64(area) > tolerance * length64(edge)
	case 3:
		normal := cross64(points[1].point - base, points[2].point - base)
		height := dot64(normal, candidate.point - base)
		independent = abs(height) > tolerance * length64(normal)
	}
	if !independent {
		return false
	}

	epa.vertices[epa.vertex_count] = candidate
	epa.vertex_count += 1
	return true
}

// Faces point outward, judged against a point inside the first tetrahedron. We
// can't use the origin because it may sit right on the surface when shapes just
// touch.
epa_add_face :: proc(epa: ^EPA, corners: [3]int) -> bool {
	slot := -1
	for face, i in epa.faces {
		if !face.alive {
			slot = i
			break
		}
	}
	if slot == -1 {
		return false
	}

	p0 := epa.vertices[corners[0]].point
	p1 := epa.vertices[corners[1]].point
	p2 := epa.vertices[corners[2]].point
	normal := cross64(p1 - p0, p2 - p0)
	magnitude := length64(normal)
	if magnitude == 0 {
		return false
	}
	normal /= magnitude
	face := EPA_Face {
		vertices = corners,
		normal   = normal,
		alive    = true,
	}
	if dot64(normal, p0 - epa.interior) < 0 {
		face.normal = -normal
		face.vertices = {corners[0], corners[2], corners[1]}
	}
	face.distance = max(dot64(face.normal, p0), 0)
	epa.faces[slot] = face
	return true
}

epa_closest_face :: proc(epa: ^EPA) -> int {
	best := -1
	for face, i in epa.faces {
		if face.alive && (best == -1 || face.distance < epa.faces[best].distance) {
			best = i
		}
	}
	return best
}

// Remove every face the new vertex can see, then patch the hole with faces
// joining it to the edges around the hole.
epa_expand :: proc(epa: ^EPA, vertex: Support_Point) -> bool {
	edges: [EPA_MAX_EDGES][2]int
	edge_count := 0
	for &face in epa.faces {
		if !face.alive || dot64(face.normal, vertex.point) - face.distance <= 0 {
			continue
		}
		face.alive = false
		for i in 0 ..< 3 {
			edge := [2]int{face.vertices[i], face.vertices[(i + 1) % 3]}
			shared := -1
			for j in 0 ..< edge_count {
				if edges[j][0] == edge[1] && edges[j][1] == edge[0] {
					shared = j
					break
				}
			}
			if shared != -1 {
				edges[shared] = edges[edge_count - 1]
				edge_count -= 1
				continue
			}
			if edge_count == EPA_MAX_EDGES {
				return false
			}
			edges[edge_count] = edge
			edge_count += 1
		}
	}
	if edge_count == 0 {
		return false
	}

	index := epa.vertex_count
	epa.vertices[index] = vertex
	epa.vertex_count += 1
	for edge in edges[:edge_count] {
		if !epa_add_face(epa, {edge[0], edge[1], index}) {
			return false
		}
	}
	return true
}

epa_witness :: proc(epa: ^EPA, face_index: int) -> Penetration {
	face := epa.faces[face_index]
	weights := barycentric(
		face.normal * face.distance,
		epa.vertices[face.vertices[0]].point,
		epa.vertices[face.vertices[1]].point,
		epa.vertices[face.vertices[2]].point,
	)
	result := Penetration {
		depth  = face.distance,
		normal = face.normal,
	}
	for i in 0 ..< 3 {
		result.a += epa.vertices[face.vertices[i]].a * weights[i]
		result.b += epa.vertices[face.vertices[i]].b * weights[i]
	}
	return result
}

barycentric :: proc(point, p0, p1, p2: [3]f64) -> [3]f64 {
	v0, v1, v2 := p1 - p0, p2 - p0, point - p0
	d00, d01, d11 := dot64(v0, v0), dot64(v0, v1), dot64(v1, v1)
	d20, d21 := dot64(v2, v0), dot64(v2, v1)
	denominator := d00 * d11 - d01 * d01
	if denominator == 0 {
		return {1.0 / 3, 1.0 / 3, 1.0 / 3}
	}

	v := (d11 * d20 - d01 * d21) / denominator
	w := (d00 * d21 - d01 * d20) / denominator
	return {1 - v - w, v, w}
}

cross64 :: proc(a, b: [3]f64) -> [3]f64 {
	return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}
}
