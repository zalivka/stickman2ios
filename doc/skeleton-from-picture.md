# A picture into the app skeleton

The app stores a skeleton as a tree of points. One point is the base and has no `par`. Every other point has exactly one `par`. A bone is the straight segment from a point to its parent. A loop is not a skeleton: closing the head would give the crown two parents. Y points down, the same way as image rows. A genskel unit looks like `stickman/app/helpers/genskel/ostrich_model.xml`: `id`, `x`, `y`, `name`, and `par` on every point except the base.

Zhang-Suen thinning is `skeleton` in `tools/bonepaper_gen/flat.py`. `lineart.py` and `ink.py` call it. `skeleton_paths` then walks the centre line and splits it where a pixel has a neighbour count other than 2. It starts with `prune_l_corners`, which also lives in `flat.py`. An 8-connected diagonal is a junction at every staircase corner until those corners are removed, and a chin comes out as a row of dashes.

scikit-image `skeletonize(..., method="zhang")` and `cv2.ximgproc.thinning(..., THINNING_ZHANGSUEN)` (in `opencv-contrib-python`) are the same algorithm. Neither is in the bonepaper venv. Neither removes the L-corners, so `prune_l_corners` stays.

Reviewed pictures, gitignored, under `tools/bonepaper_gen/out/`: `stick_skel` (a thin ink stick figure) and `blob_skel` (a filled black silhouette). Ink was `R+G+B < 380`. `skeleton.png` is the centre line. `tree.png` is the tree drawn over the original.

## From centre line to tree

`np.nonzero` yields `(row, col)`, so a point is `(y, x)` until it is written as `x` and `y`.

1. Thin, prune L-corners, walk paths.
2. Drop a path shorter than 8 px. On the thin figure, 8 of the 14 paths were 2 px. They are the clump of pixels where strokes cross, not bones. Cluster the remaining endpoints that sit within 3 px, and treat them as one joint.
3. A path whose two ends fall in the same cluster is a loop. The thin figure's head was a 936 px loop whose ends were 1 px apart. It has one exit, where the neck meets the oval. The child is the pixel on the loop farthest from that exit, the crown. The rest of the oval is deleted. A filled head does not make a loop: the blob's head thinned to an open chain from the crown down to the shoulder.
4. A limb's centre line stops about half a torso-width short of the torso's centre line. The blob's left arm ended 43.7 px from the shoulder, and that end had degree 1. Join a degree-1 end to the nearest joint of degree 3 or more when the gap is at most 60 px and the straight line stays inside the ink. The arm then shares the shoulder, and the gap is not an extra node.
5. The base is the joint of degree 3 or more with the largest `y`, the crotch. The lowest pixel of any kind is a foot. That choice put the red base on the thin figure's right foot the first time.
6. Simplify each chain with Douglas-Peucker, walking away from the base. Endpoints stay. A new node appears only where the ink leaves the straight bone by more than the tolerance. Do not drop a node in the middle of a straight segment: this does not invent an elbow or a knee.

Tolerance is 12 px on a thin stroke. That is above the wobble of the line and below a real bend, and the thin figure came out at 14 nodes and 13 bones. A filled silhouette's medial axis wanders with the outline, so 12 px turns the wobble into joints. 24 px kept the blob's torso (deviation 14.6) and its left arm (9.9) as one bone each. The right arm deviates 62.9 and the curved leg 25.4, so each of those kept one node. The head deviates 20.9 and stayed one bone. The blob came out at 9 nodes and 8 bones.

Write the points as absolute `x`, `y`, with `par` pointing toward the base.
