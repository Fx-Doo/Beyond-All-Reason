--[[
	MapGen v2 - GPU side of the map transform (GLSL source held in Lua long strings).

	This is a GLSL port of transform.lua's tap evaluation. The Lua side flattens a Transform into the `prog` float
	array (Transform:program(), 20 floats per node, see "PACKED PROGRAM LAYOUT" below) and this shader interprets it.

	Vocabulary used throughout the GLSL:
	  out position  (outX, outZ) = a texel of the OUTPUT (generated) map; vec2 `outPos`, x = X, y = Z.
	  src position  (srcX, srcZ) = the place in the ORIGINAL map that the output texel copies from; vec2 `srcPos`.
	  tap           = one source position that contributes to an output texel. Seams blend several taps, each one
	                  with its own blend weight; the final colour is the weight-sum of all taps.
	  Jacobian      = 2x2 matrix d(srcPos) / d(outPos) of the chain at that tap. Vector-valued textures (normals)
	                  are turned with it so they follow the terrain they were copied from.

	The pieces are concatenated by Shader.fragment(kind):
	  "#version 120" + head + (fetchTiled | fetchWhole | fetchNormals) + gather + mainGL
	`head` + `gather` are plain GLSL that compiles as #version 120 and as 330 (the tests use the latter).
	Note for the tests: they cut each string out with a regex up to the first closing double square bracket, so
	the GLSL must never contain that character pair.
]]

local Shader = {}

-- Transform.MAX_NODES * Transform.NODE_STRIDE; must match `uniform float prog[400]` below.
Shader.PROG_FLOATS = 400

------------------------------------------------------------------------------------------------------------------------
-- Shader.head: uniforms and small math helpers shared by every variant
------------------------------------------------------------------------------------------------------------------------
-- PACKED PROGRAM LAYOUT (`prog`): node n (0-based) starts at base = n * 20 and owns 5 vec4-sized slots:
--   slot 0 (base+0..3)   : kind, next, aheadHead, behindHead   (node references are 1-based, 0 = end of chain)
--   slot 1 (base+4..7), slot 2 (base+8..11), slot 3 (base+12..15), slot 4 (base+16..19): parameters per kind
-- kind 1 reflect/rotate : s1 = (linePointX, linePointZ, lineDirX, lineDirZ)
--                         s2 = (sideSign, band, isRotate, always)
--                         s3 = (rotCenterX, rotCenterZ, rotCos, rotSin)   [rotate only]
--                         s4 = (waveAmp, waveFreq, wavePhase, waveEnabled)
-- kind 2 nfold          : s1 = (centerX, centerZ, sectorCount, phase)
--                         s2 = (mirror, band, twist, wedge)
--                         s3 = (ring, ringMirror, 0, 0)
-- kind 3 tile           : s1 = (originX, originZ, cos, sin)   s2 = (cellWidth, cellHeight, mirror, band)
-- kind 4 warp           : s1 = (amplitude, frequency, phaseForX, phaseForZ)
-- kind 5 zoom           : s1 = (centerX, centerZ, targetX, targetZ)   s2 = (scale, cos, sin, 0)
-- kind 6 select         : slot 0 carries both heads; s1 = (maskType 1 = line / 2 = disc, band, sign, 0)
--                         s2 = line: (pointX, pointZ, dirX, dirZ)   disc: (centerX, centerZ, radius, 0)
-- kind 7 wallpaper      : s1 = (originX, originZ, cos, sin)
--                         s2 = (cellSize, group 1 = p4m / 2 = p3m1 / 3 = p6m, 0, 0)
-- kind 8 patch          : s1 = (outCenterX, outCenterZ, srcCenterX, srcCenterZ)   s2 = (m00, m01, m10, m11)
--                         (written by patches.lua, a single node)
Shader.head = [[
uniform float prog[400];
uniform vec4 mapInfo;   // map width, map depth (world units), node count, unused
uniform vec4 outInfo;   // world origin x, z of the output rectangle, its extent x, z
uniform vec4 passInfo;  // tiled mode: source tile x, z, tile size, unused
uniform vec4 tileInfo;  // tiled mode: tiles in x, z
uniform vec4 maskInfo;  // patch disc: centre x, z, solid radius, outer radius (outer 0 = no mask)
uniform vec4 maskMode;  // x: 1 = write only the mask weight into alpha (used to clear the area before a patch is added)

const float TWO_PI = 6.28318530717959;

// Builds a mat2 from its rows given in reading order (GLSL matrices are column major).
mat2 matFromRows(float m00, float m01, float m10, float m11) {
	return mat2(m00, m10, m01, m11);
}

// Smoothstep from 0 to 1 over t in [0, 1] (t is clamped).
float smooth01(float t) {
	t = clamp(t, 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

// Weight (0..1) of the "positive side" of a seam. signedDist < 0 is the positive side; bandWidth is the half width
// of the soft transition (0 = hard edge).
float seamWeight(float signedDist, float bandWidth) {
	if (bandWidth <= 0.0) {
		return signedDist < 0.0 ? 1.0 : 0.0;
	}
	return smooth01((bandWidth - signedDist) / (2.0 * bandWidth));
}

// Wavy offset of a seam: a sum of three sines/cosines of t (the three harmonics are 1x, 3x and 5x frequency).
float waveOffset(float t, float amplitude, float freq, float phase) {
	return amplitude * (
		0.5 * sin(t * freq + phase)
		+ 0.25 * sin(t * freq * 3.0 + phase * 0.5)
		+ 0.25 * cos(t * freq * 5.0 + phase * 1.5)
	);
}

// Derivative of waveOffset with respect to t.
float waveSlope(float t, float amplitude, float freq, float phase) {
	return amplitude * freq * (
		0.5 * cos(t * freq + phase)
		+ 0.75 * cos(t * freq * 3.0 + phase * 0.5)
		- 1.25 * sin(t * freq * 5.0 + phase * 1.5)
	);
}

// Positions outside the map are reflected back inside (the map is mirrored endlessly); flipSign is the sign flip of
// each axis (for the Jacobian).
vec2 foldMapPos(vec2 pos, out vec2 flipSign) {
	vec2 folded = mod(pos, 2.0 * mapInfo.xy);
	flipSign = vec2(1.0);
	if (folded.x > mapInfo.x) {
		folded.x = 2.0 * mapInfo.x - folded.x;
		flipSign.x = -1.0;
	}
	if (folded.y > mapInfo.y) {
		folded.y = 2.0 * mapInfo.y - folded.y;
		flipSign.y = -1.0;
	}
	return folded;
}

// Wraps coord into [0, period); with mirrorFlag every second period runs backwards (triangle wave).
// (Not used by the current program kinds.)
float foldAxis(float coord, float period, float mirrorFlag) {
	if (mirrorFlag > 0.5) {
		float wrapped = mod(coord, 2.0 * period);
		if (wrapped > period) {
			wrapped = 2.0 * period - wrapped;
		}
		return wrapped;
	}
	return mod(coord, period);
}

// Slope (+1 / -1) of foldAxis. (Not used by the current program kinds.)
float foldSlope(float coord, float period, float mirrorFlag) {
	if (mirrorFlag > 0.5 && mod(coord, 2.0 * period) > period) {
		return -1.0;
	}
	return 1.0;
}

// Radial fold of the nfold ring option: wraps the radius into [0, ring), mirrored on every second ring if
// ringMirror is set; slope = d foldedRadius / d radius.
float ringFold(float radius, float ring, float ringMirror, out float slope) {
	slope = 1.0;
	if (ring <= 0.0) {
		return radius;
	}
	if (ringMirror > 0.5) {
		float wrapped = mod(radius, 2.0 * ring);
		if (wrapped > ring) {
			slope = -1.0;
			return 2.0 * ring - wrapped;
		}
		return wrapped;
	}
	return mod(radius, ring);
}

// nfold: position (in the original map) of the image of the polar point (theta, radius) in sector `sector`.
// sectorAngle = 2 pi / sectorCount; the sector is optionally mirrored (mirrorFlag) and its angular extent scaled by
// `wedge`; `ring` / `ringMirror` fold the radius.
vec2 sectorMap(
	float sector, float theta, float radius, vec2 center, float sectorAngle, float phase,
	float mirrorFlag, float wedge, float ring, float ringMirror, float sectorCount
) {
	float angleInSector = theta - sector * sectorAngle;
	if (mirrorFlag > 0.5 && mod(mod(sector, sectorCount), 2.0) > 0.5) {
		angleInSector = sectorAngle - angleInSector;
	}
	float srcAngle = phase + wedge * angleInSector;
	float unusedSlope;
	float foldedRadius = ringFold(radius, ring, ringMirror, unusedSlope);
	return center + foldedRadius * vec2(cos(srcAngle), sin(srcAngle));
}

// nfold: Jacobian d(srcPos) / d(outPos) of sectorMap. rawTheta is the polar angle of the output point before the
// twist is applied; twist is the spiral term (theta = rawTheta - phase + twist * radius).
mat2 sectorJac(
	float sector, float theta, float radius, float rawTheta, float sectorAngle, float phase,
	float mirrorFlag, float wedge, float twist, float ring, float ringMirror, float sectorCount
) {
	float flipSign = 1.0;
	float angleInSector = theta - sector * sectorAngle;
	if (mirrorFlag > 0.5 && mod(mod(sector, sectorCount), 2.0) > 0.5) {
		angleInSector = sectorAngle - angleInSector;
		flipSign = -1.0;
	}
	float srcAngle = phase + wedge * angleInSector;
	float radialSlope;
	float foldedRadius = ringFold(radius, ring, ringMirror, radialSlope);
	vec2 srcRadialDir = vec2(cos(srcAngle), sin(srcAngle));
	vec2 srcTangentDir = vec2(-srcRadialDir.y, srcRadialDir.x);
	// how srcPos moves for a unit step of the output point along / across its own radial direction
	vec2 srcPerRadial = radialSlope * srcRadialDir + foldedRadius * flipSign * wedge * twist * srcTangentDir;
	vec2 srcPerTangent = (foldedRadius * flipSign * wedge / radius) * srcTangentDir;
	vec2 outRadialDir = vec2(cos(rawTheta), sin(rawTheta));
	vec2 outTangentDir = vec2(-outRadialDir.y, outRadialDir.x);
	return matFromRows(
		srcPerRadial.x * outRadialDir.x + srcPerTangent.x * outTangentDir.x,
		srcPerRadial.x * outRadialDir.y + srcPerTangent.x * outTangentDir.y,
		srcPerRadial.y * outRadialDir.x + srcPerTangent.y * outTangentDir.x,
		srcPerRadial.y * outRadialDir.y + srcPerTangent.y * outTangentDir.y
	);
}

// Wallpaper mirror lines of the fundamental triangle of wallpaper group `group` (1 = p4m, 2 = p3m1, 3 = p6m);
// lineIdx 0..2 picks the line. Result: (point x, point z, inward normal x, inward normal z), see transform.lua.
vec4 wallLine(float group, int lineIdx) {
	if (group < 1.5) {
		if (lineIdx == 0) return vec4(0.0, 0.0, 0.0, 1.0);
		if (lineIdx == 1) return vec4(1.0, 0.0, -1.0, 0.0);
		return vec4(0.0, 0.0, 0.7071067811865476, -0.7071067811865476);
	}
	if (group < 2.5) {
		if (lineIdx == 0) return vec4(0.0, 0.0, 0.0, 1.0);
		if (lineIdx == 1) return vec4(0.0, 0.0, 0.8660254037844386, -0.5);
		return vec4(1.0, 0.0, -0.8660254037844386, -0.5);
	}
	if (lineIdx == 0) return vec4(0.0, 0.0, 0.0, 1.0);
	if (lineIdx == 1) return vec4(0.0, 0.0, 0.5, -0.8660254037844386);
	return vec4(1.0, 0.0, -0.8660254037844386, -0.5);
}

// Blend weight (0..1) of a neighbouring tile cell, from the distance to the shared border; 0 outside the band.
float neighbourWeight(float borderDist, float bandWidth) {
	if (borderDist >= bandWidth) {
		return 0.0;
	}
	return smooth01((bandWidth - borderDist) / (2.0 * bandWidth));
}

// Tile cell (cellI, cellJ) seen at frame position (frameU, frameV): returns the frame position of the point it shows
// (cellSize = cell width, height), plus the flip signs of the cell (-1 on an axis where a mirrored cell is flipped).
vec2 tileCell(
	float frameU, float frameV, float cellI, float cellJ, vec2 cellSize, float mirrorFlag, out vec2 flipSign
) {
	float cellU = frameU - cellI * cellSize.x;
	float cellV = frameV - cellJ * cellSize.y;
	flipSign = vec2(1.0);
	if (mirrorFlag > 0.5) {
		if (mod(cellI, 2.0) > 0.5) {
			cellU = cellSize.x - cellU;
			flipSign.x = -1.0;
		}
		if (mod(cellJ, 2.0) > 0.5) {
			cellV = cellSize.y - cellV;
			flipSign.y = -1.0;
		}
	}
	return vec2(cellU, cellV);
}
]]

------------------------------------------------------------------------------------------------------------------------
-- Shader.gather: the chain interpreter
------------------------------------------------------------------------------------------------------------------------
-- Walks the node chain for one output position. Every node maps the current position one step towards the original
-- map; nodes with a soft seam split the walk in two taps (the second one is parked on a small stack together with its
-- blend weight and Jacobian and resumed once the first one has reached the end of the chain). At the end of a chain
-- the tap is sampled with fetchTap() and added to the result, scaled by its blend weight.
-- Needs a function vec4 fetchTap(vec2 srcPos, mat2 jac) declared before it.
Shader.gather = [[
vec4 gatherTaps(vec2 outPos) {
	// stack of parked taps (second branches of seams that still have to be walked)
	vec2 stackPos[16];
	mat2 stackJac[16];
	float stackWeight[16];
	int stackNode[16];
	int stackTop = 0;

	vec4 accum = vec4(0.0);
	vec2 curPos = outPos;      // current position along the chain (ends up as the src position of the tap)
	mat2 curJac = mat2(1.0);   // Jacobian d(curPos) / d(outPos) so far
	float curWeight = 1.0;     // blend weight of the tap currently being walked
	int node = mapInfo.z > 0.5 ? 0 : -1;

	for (int iteration = 0; iteration < 512; iteration++) {
		if (node < 0) {
			// end of the chain: sample the original map and continue with a parked tap, if any
			accum += curWeight * fetchTap(curPos, curJac);
			if (stackTop == 0) {
				break;
			}
			stackTop--;
			curPos = stackPos[stackTop];
			curJac = stackJac[stackTop];
			curWeight = stackWeight[stackTop];
			node = stackNode[stackTop];
		} else {
			int base = node * 20;
			int kind = int(prog[base] + 0.5);
			int nextNode = int(prog[base + 1] + 0.5) - 1;

			if (kind == 6) {
				// select: pick between two sub-chains with a line or disc mask (slot 0 holds both heads)
				int headA = int(prog[base + 2] + 0.5) - 1;
				int headB = int(prog[base + 3] + 0.5) - 1;
				float seamBand = prog[base + 5];
				float weightB;
				if (prog[base + 4] < 1.5) {
					vec2 linePoint = vec2(prog[base + 8], prog[base + 9]);
					vec2 lineDir = vec2(prog[base + 10], prog[base + 11]);
					float sideSign = prog[base + 6];
					weightB = seamWeight(dot(curPos - linePoint, vec2(-lineDir.y, lineDir.x)) * sideSign, seamBand);
				} else {
					vec2 discCenter = vec2(prog[base + 8], prog[base + 9]);
					float discRadius = prog[base + 10];
					weightB = seamWeight(length(curPos - discCenter) - discRadius, seamBand);
				}
				if (weightB <= 0.0) {
					node = headA;
				} else if (weightB >= 1.0) {
					node = headB;
				} else {
					if (stackTop < 16) {
						stackPos[stackTop] = curPos;
						stackJac[stackTop] = curJac;
						stackWeight[stackTop] = curWeight * weightB;
						stackNode[stackTop] = headB;
						stackTop++;
					}
					curWeight *= (1.0 - weightB);
					node = headA;
				}
			} else {
				// Every other kind produces up to two candidate positions: A (the transformed one) and B (the
				// untouched or neighbouring one); blendA is the weight of A. blendA == 1 -> only A, 0 -> only B.
				vec2 posA = curPos;
				vec2 posB = curPos;
				mat2 jacA = mat2(1.0);
				mat2 jacB = mat2(1.0);
				float blendA = 0.0;

				if (kind == 1) {
					// reflect / rotate across a (possibly wavy) line: only the side given by sideSign is replaced
					vec2 linePoint = vec2(prog[base + 4], prog[base + 5]);
					vec2 lineDir = vec2(prog[base + 6], prog[base + 7]);
					vec2 lineNormal = vec2(-lineDir.y, lineDir.x);
					float sideSign = prog[base + 8];
					float seamBand = prog[base + 9];
					float isRotate = prog[base + 10];
					float alwaysApply = prog[base + 11];
					vec2 relPos = curPos - linePoint;
					float signedDist = dot(relPos, lineNormal);  // distance to the line, along its normal
					vec2 distGradient = lineNormal;              // d signedDist / d curPos
					if (prog[base + 19] > 0.5) {
						float waveAmp = prog[base + 16];
						float waveFreq = prog[base + 17];
						float wavePhase = prog[base + 18];
						float alongLine = dot(relPos, lineDir);
						signedDist -= waveOffset(alongLine, waveAmp, waveFreq, wavePhase);
						distGradient -= waveSlope(alongLine, waveAmp, waveFreq, wavePhase) * lineDir;
					}
					blendA = seamWeight(signedDist * sideSign, seamBand);
					if (alwaysApply > 0.5) {
						blendA = 1.0;
					}
					if (blendA > 0.0) {
						if (isRotate > 0.5) {
							vec2 rotCenter = vec2(prog[base + 12], prog[base + 13]);
							float rotCos = prog[base + 14];
							float rotSin = prog[base + 15];
							vec2 relCenter = curPos - rotCenter;
							posA = rotCenter + vec2(relCenter.x * rotCos - relCenter.y * rotSin,
								relCenter.x * rotSin + relCenter.y * rotCos);
							jacA = matFromRows(rotCos, -rotSin, rotSin, rotCos);
						} else {
							posA = curPos - 2.0 * signedDist * lineNormal;
							jacA = matFromRows(
								1.0 - 2.0 * lineNormal.x * distGradient.x, -2.0 * lineNormal.x * distGradient.y,
								-2.0 * lineNormal.y * distGradient.x, 1.0 - 2.0 * lineNormal.y * distGradient.y
							);
						}
					}
				} else if (kind == 2) {
					// nfold: fold the plane into sectorCount sectors around a centre (kaleidoscope), with optional
					// mirroring, spiral twist, wedge scaling, radial ring folding and soft sector borders
					vec2 center = vec2(prog[base + 4], prog[base + 5]);
					float sectorCount = prog[base + 6];
					float phase = prog[base + 7];
					float mirrorFlag = prog[base + 8];
					float seamBand = prog[base + 9];
					float twist = prog[base + 10];
					float wedge = prog[base + 11];
					float ring = prog[base + 12];
					float ringMirror = prog[base + 13];
					float sectorAngle = TWO_PI / sectorCount;
					vec2 toCenter = curPos - center;
					float radius = length(toCenter);
					if (radius >= 1e-6) {
						float rawTheta = atan(toCenter.y, toCenter.x);
						float theta = mod(rawTheta - phase + twist * radius, TWO_PI);
						float sector = floor(theta / sectorAngle);
						float sectorFrac = theta / sectorAngle - sector;   // 0..1 across the sector
						posA = sectorMap(sector, theta, radius, center, sectorAngle, phase,
							mirrorFlag, wedge, ring, ringMirror, sectorCount);
						jacA = sectorJac(sector, theta, radius, rawTheta, sectorAngle, phase,
							mirrorFlag, wedge, twist, ring, ringMirror, sectorCount);
						blendA = 1.0;
						if (seamBand > 0.0) {
							// near a sector border blend with the neighbouring sector
							float distToLowerEdge = sectorFrac * sectorAngle * radius;
							float distToUpperEdge = (1.0 - sectorFrac) * sectorAngle * radius;
							if (distToLowerEdge < seamBand) {
								blendA = 1.0 - smooth01((seamBand - distToLowerEdge) / (2.0 * seamBand));
								posB = sectorMap(sector - 1.0, theta, radius, center, sectorAngle, phase,
									mirrorFlag, wedge, ring, ringMirror, sectorCount);
								jacB = sectorJac(sector - 1.0, theta, radius, rawTheta, sectorAngle, phase,
									mirrorFlag, wedge, twist, ring, ringMirror, sectorCount);
							} else if (distToUpperEdge < seamBand) {
								blendA = 1.0 - smooth01((seamBand - distToUpperEdge) / (2.0 * seamBand));
								posB = sectorMap(sector + 1.0, theta, radius, center, sectorAngle, phase,
									mirrorFlag, wedge, ring, ringMirror, sectorCount);
								jacB = sectorJac(sector + 1.0, theta, radius, rawTheta, sectorAngle, phase,
									mirrorFlag, wedge, twist, ring, ringMirror, sectorCount);
							}
						}
					}
				} else if (kind == 3) {
					// tile: repeat a cellWidth x cellHeight cell over the plane (in a frame rotated by the origin
					// angle), optionally mirrored; near cell borders up to three neighbour cells are blended in
					vec2 frameOrigin = vec2(prog[base + 4], prog[base + 5]);
					float frameCos = prog[base + 6];
					float frameSin = prog[base + 7];
					vec2 cellSize = vec2(prog[base + 8], prog[base + 9]);
					float mirrorFlag = prog[base + 10];
					float seamBand = prog[base + 11];
					vec2 relPos = curPos - frameOrigin;
					float frameU = relPos.x * frameCos + relPos.y * frameSin;
					float frameV = -relPos.x * frameSin + relPos.y * frameCos;
					mat2 frameRot = matFromRows(frameCos, -frameSin, frameSin, frameCos);
					mat2 frameRotInv = matFromRows(frameCos, frameSin, -frameSin, frameCos);
					float cellI = floor(frameU / cellSize.x);
					float cellJ = floor(frameV / cellSize.y);
					vec2 flipSign;
					vec2 cellPos = tileCell(frameU, frameV, cellI, cellJ, cellSize, mirrorFlag, flipSign);
					posA = frameOrigin + vec2(cellPos.x * frameCos - cellPos.y * frameSin,
						cellPos.x * frameSin + cellPos.y * frameCos);
					jacA = frameRot * matFromRows(flipSign.x, 0.0, 0.0, flipSign.y) * frameRotInv;
					blendA = 1.0;
					if (seamBand > 0.0) {
						// up to three more taps from the neighbouring cells, blended near the borders
						float inCellU = frameU - cellI * cellSize.x;
						float inCellV = frameV - cellJ * cellSize.y;
						float neighbourStepU = inCellU < cellSize.x - inCellU ? -1.0 : 1.0;
						float neighbourStepV = inCellV < cellSize.y - inCellV ? -1.0 : 1.0;
						float weightU = neighbourWeight(min(inCellU, cellSize.x - inCellU), seamBand);
						float weightV = neighbourWeight(min(inCellV, cellSize.y - inCellV), seamBand);
						// neighbourIdx 1 = across the U border, 2 = across the V border, 3 = diagonal
						for (int neighbourIdx = 1; neighbourIdx < 4; neighbourIdx++) {
							float neighbourI = cellI + (neighbourIdx == 1 || neighbourIdx == 3 ? neighbourStepU : 0.0);
							float neighbourJ = cellJ + (neighbourIdx >= 2 ? neighbourStepV : 0.0);
							float neighbourBlend = (neighbourIdx == 1) ? weightU * (1.0 - weightV)
								: ((neighbourIdx == 2) ? weightV * (1.0 - weightU) : weightU * weightV);
							if (neighbourBlend > 1e-9 && stackTop < 15) {
								vec2 neighbourFlip;
								vec2 neighbourCell = tileCell(frameU, frameV, neighbourI, neighbourJ, cellSize,
									mirrorFlag, neighbourFlip);
								stackPos[stackTop] = frameOrigin + vec2(
									neighbourCell.x * frameCos - neighbourCell.y * frameSin,
									neighbourCell.x * frameSin + neighbourCell.y * frameCos);
								stackJac[stackTop] = frameRot * matFromRows(neighbourFlip.x, 0.0, 0.0, neighbourFlip.y)
									* frameRotInv * curJac;
								stackWeight[stackTop] = curWeight * neighbourBlend;
								stackNode[stackTop] = nextNode;
								stackTop++;
							}
						}
						curWeight *= (1.0 - weightU) * (1.0 - weightV);
					}
				} else if (kind == 7) {
					// wallpaper: fold the plane into the fundamental triangle of a wallpaper group by repeatedly
					// mirroring across its three lines (in a frame rotated and scaled by cellScale)
					vec2 frameOrigin = vec2(prog[base + 4], prog[base + 5]);
					float frameCos = prog[base + 6];
					float frameSin = prog[base + 7];
					float cellScale = prog[base + 8];
					float group = prog[base + 9];
					vec2 relPos = curPos - frameOrigin;
					// position in triangle space (one cell = 1 unit)
					vec2 triPos = vec2(relPos.x * frameCos + relPos.y * frameSin,
						-relPos.x * frameSin + relPos.y * frameCos) / cellScale;
					mat2 foldJac = mat2(1.0);   // accumulated reflections
					for (int foldPass = 0; foldPass < 128; foldPass++) {
						bool moved = false;
						for (int lineIdx = 0; lineIdx < 3; lineIdx++) {
							vec4 mirrorLine = wallLine(group, lineIdx);   // (point x, point z, normal x, normal z)
							float distToLine = (triPos.x - mirrorLine.x) * mirrorLine.z
								+ (triPos.y - mirrorLine.y) * mirrorLine.w;
							if (distToLine < -1e-6) {
								triPos -= 2.0 * distToLine * mirrorLine.zw;
								foldJac = matFromRows(
									1.0 - 2.0 * mirrorLine.z * mirrorLine.z, -2.0 * mirrorLine.z * mirrorLine.w,
									-2.0 * mirrorLine.z * mirrorLine.w, 1.0 - 2.0 * mirrorLine.w * mirrorLine.w
								) * foldJac;
								moved = true;
							}
						}
						if (!moved) {
							break;
						}
					}
					triPos *= cellScale;
					posA = frameOrigin + vec2(triPos.x * frameCos - triPos.y * frameSin,
						triPos.x * frameSin + triPos.y * frameCos);
					jacA = matFromRows(frameCos, -frameSin, frameSin, frameCos) * foldJac
						* matFromRows(frameCos, frameSin, -frameSin, frameCos);
					blendA = 1.0;
				} else if (kind == 4) {
					// warp: displace every position by a wave of the other coordinate
					float warpAmp = prog[base + 4];
					float warpFreq = prog[base + 5];
					float phaseForX = prog[base + 6];
					float phaseForZ = prog[base + 7];
					posA = curPos + vec2(waveOffset(curPos.y, warpAmp, warpFreq, phaseForX),
						waveOffset(curPos.x, warpAmp, warpFreq, phaseForZ));
					jacA = matFromRows(1.0, waveSlope(curPos.y, warpAmp, warpFreq, phaseForX),
						waveSlope(curPos.x, warpAmp, warpFreq, phaseForZ), 1.0);
					blendA = 1.0;
				} else if (kind == 8) {
					// patch: exact affine copy, original = M * (outPos - Q) + P (see patches.lua)
					vec2 patchOutPos = vec2(prog[base + 4], prog[base + 5]);
					vec2 patchSrcPos = vec2(prog[base + 6], prog[base + 7]);
					mat2 patchMat = matFromRows(prog[base + 8], prog[base + 9], prog[base + 10], prog[base + 11]);
					posA = patchSrcPos + patchMat * (curPos - patchOutPos);
					jacA = patchMat;
					blendA = 1.0;
				} else {
					// zoom (kind 5): scale by 1 / zoomScale around zoomCenter, rotate, move to zoomTarget
					vec2 zoomCenter = vec2(prog[base + 4], prog[base + 5]);
					vec2 zoomTarget = vec2(prog[base + 6], prog[base + 7]);
					float zoomScale = prog[base + 8];
					float zoomCos = prog[base + 9];
					float zoomSin = prog[base + 10];
					vec2 relCenter = (curPos - zoomCenter) / zoomScale;
					posA = zoomTarget + vec2(relCenter.x * zoomCos - relCenter.y * zoomSin,
						relCenter.x * zoomSin + relCenter.y * zoomCos);
					jacA = matFromRows(
						zoomCos / zoomScale, -zoomSin / zoomScale,
						zoomSin / zoomScale, zoomCos / zoomScale
					);
					blendA = 1.0;
				}

				// continue with A, B, or (soft seam) park one of them on the stack and continue with the other
				if (blendA >= 1.0) {
					curPos = posA;
					curJac = jacA * curJac;
				} else if (blendA <= 0.0) {
					curPos = posB;
					curJac = jacB * curJac;
				} else {
					if (stackTop < 16) {
						stackPos[stackTop] = posA;
						stackJac[stackTop] = jacA * curJac;
						stackWeight[stackTop] = curWeight * blendA;
						stackNode[stackTop] = nextNode;
						stackTop++;
					}
					curWeight *= (1.0 - blendA);
					curPos = posB;
					curJac = jacB * curJac;
				}
				node = nextNode;
			}
		}
	}
	return accum;
}
]]

------------------------------------------------------------------------------------------------------------------------
-- Shader.fetch*: how a tap is sampled from the original map (all define vec4 fetchTap(vec2 srcPos, mat2 jac))
------------------------------------------------------------------------------------------------------------------------

-- Source tile of a tiled map texture: contributes only the taps that land inside the tile.
Shader.fetchTiled = [[
uniform sampler2D src;
vec4 fetchTap(vec2 srcPos, mat2 jac) {
	vec2 flipSign;
	srcPos = foldMapPos(srcPos, flipSign);
	float tileSize = passInfo.z;
	float tileX = min(floor(srcPos.x / tileSize), tileInfo.x - 1.0);
	float tileZ = min(floor(srcPos.y / tileSize), tileInfo.y - 1.0);
	if (tileX != passInfo.x || tileZ != passInfo.y) {
		return vec4(0.0);
	}
	return texture2D(src, (srcPos - vec2(tileX, tileZ) * tileSize) / tileSize);
}
]]

-- Map-wide texture sampled over the whole map in one go.
Shader.fetchWhole = [[
uniform sampler2D src;
vec4 fetchTap(vec2 srcPos, mat2 jac) {
	vec2 flipSign;
	srcPos = foldMapPos(srcPos, flipSign);
	return texture2D(src, srcPos / mapInfo.xy);
}
]]

-- Map-wide tangent-space normal texture: rgb = (s, t, n) * 0.5 + 0.5 with s/t aligned to world x/z, a = blend weight.
-- The horizontal part behaves like a height gradient, so it is pulled back with J^T.
Shader.fetchNormals = [[
uniform sampler2D src;
vec4 fetchTap(vec2 srcPos, mat2 jac) {
	vec2 flipSign;
	srcPos = foldMapPos(srcPos, flipSign);
	jac = matFromRows(flipSign.x, 0.0, 0.0, flipSign.y) * jac;
	vec4 texel = texture2D(src, srcPos / mapInfo.xy);
	vec2 srcSlope = texel.xy * 2.0 - 1.0;   // horizontal part of the stored normal, in the original map
	vec2 outSlope = clamp(srcSlope * jac, vec2(-1.0), vec2(1.0));   // row vector times J = J^T applied to it
	return vec4(outSlope * 0.5 + 0.5, texel.z, texel.w);
}
]]

------------------------------------------------------------------------------------------------------------------------
-- Vertex / fragment entry points
------------------------------------------------------------------------------------------------------------------------

-- Pass-through vertex shader (the quad is already in clip space).
Shader.vertex = [[
#version 120
void main() {
	gl_Position = gl_Vertex;
	gl_TexCoord[0] = gl_MultiTexCoord0;
}
]]

-- Fragment entry: output position of the texel -> gatherTaps, scaled by the patch mask weight.
Shader.mainGL = [[
// 1 everywhere unless maskInfo describes a patch disc: 1 inside the solid radius, fading to 0 at the outer radius.
float maskWeight(vec2 outPos) {
	if (maskInfo.w <= 0.0) {
		return 1.0;
	}
	return 1.0 - smooth01((length(outPos - maskInfo.xy) - maskInfo.z) / (maskInfo.w - maskInfo.z));
}

void main() {
	vec2 uv = gl_TexCoord[0].xy;
	vec2 outPos = outInfo.xy + uv * outInfo.zw;
	float maskAmount = maskWeight(outPos);
	if (maskMode.x > 0.5) {
		// clear mode: only the mask weight goes into alpha
		gl_FragColor = vec4(0.0, 0.0, 0.0, maskAmount);
	} else {
		gl_FragColor = gatherTaps(outPos) * maskAmount;
	}
}
]]

-- kind: "tiled", "whole" or "normals". Fragment source for gl.CreateShader.
function Shader.fragment(kind)
	local fetch = Shader.fetchTiled
	if kind == "whole" then
		fetch = Shader.fetchWhole
	elseif kind == "normals" then
		fetch = Shader.fetchNormals
	end
	return "#version 120\n" .. Shader.head .. fetch .. Shader.gather .. Shader.mainGL
end

return Shader
