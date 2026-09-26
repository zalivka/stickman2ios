"""Restyled template trex, plus a walk-right then walk-left loop, for the boil demo.

The gait is the one in stickman `demo_trex` (foot-lock, same bone names and angles).
Poses are in page px at the same scale `item_restyle.py` uses for a 300 px wide trex.
Each bone is its own PNG (still + 3 boil copies) so the demo can boil and walk independently.

usage: .venv/bin/python trex_walk.py <out_dir>
"""
import json
import math
import random
import subprocess
import sys
import zipfile
from pathlib import Path

import boil
import item_boil
import item_restyle
import svg_export

REPO = Path("/Users/zalivka/ws/stickman2")
sys.path.insert(0, str(REPO))
from stickman.app.helpers.motionlib import (  # noqa: E402
    CharacterRig,
    FootLockGait,
    FootLockLeg,
    LimbChain,
    enforce_ground,
    mirror_pose,
    solve_limb_ik,
    solve_tip_chain,
)

PACK = Path("../../at_elements/packs/template.basic.atp")
DISPLAY = 300.0
PAGE_W, PAGE_H = 640.0, 480.0
FEET_Y = 0.9 * PAGE_H
GROUND_LOCAL_Y = 208.0  # rest toe y in the item, same as demo_trex

# demo_trex gait, with lengths scaled from its 0.7 scene scale into item units, then by k.
SCENE_SCALE = 0.7
CYCLES = 1.0
FRAMES = 16
DUTY = 0.66
STEP_LEN_ITEM = 88.0 / SCENE_SCALE
STEP_LIFT_ITEM = 26.0 / SCENE_SCALE
TRACK_ITEM = -15.0 / SCENE_SCALE
BOB_ITEM = 4.0 / SCENE_SCALE
THIGH_NEUTRAL = 55.0
THIGH_SWING = 45.0
THIGH_LIFT = 15.0
BODY_NOD = 1.5
TAIL_SWAY = 2.5
JAW_OPEN = 6.0
ARM_SWING = 10.0

ID_TO_NAME = {
    1: "pelvis", 2: "tail", 3: "head",
    10: "jaw_hinge", 11: "jaw",
    12: "shoulder", 13: "elbow_a", 14: "hand_a", 15: "elbow_b", 16: "hand_b",
    7: "knee_a", 8: "ankle_a", 9: "toe_a",
    4: "knee_b", 5: "ankle_b", 6: "toe_b",
}
NAME_TO_ID = {name: pid for pid, name in ID_TO_NAME.items()}
HEAD_CHAIN = ("tail", "head", "jaw_hinge", "shoulder", "jaw", "elbow_a", "hand_a", "elbow_b", "hand_b")
HEAD_DESCENDANTS = ("jaw_hinge", "shoulder", "jaw", "elbow_a", "hand_a", "elbow_b", "hand_b")
LEG_A = LimbChain("a", "knee_a", "ankle_a", "toe_a", (-1.0, 0.0))
LEG_B = LimbChain("b", "knee_b", "ankle_b", "toe_b", (-1.0, 0.0))


def upper_body_angles(rig, g):
    one = 2.0 * math.pi * g
    two = 2.0 * one
    ang = {name: default for name, (_, _, default) in rig.bones.items()}
    nod = BODY_NOD * math.cos(two)
    ang["head"] += nod
    for name in HEAD_DESCENDANTS:
        ang[name] += nod
    ang["tail"] -= TAIL_SWAY * math.sin(two)
    ang["jaw"] += JAW_OPEN * (0.5 + 0.5 * math.sin(one))
    arm = ARM_SWING * math.sin(one)
    ang["elbow_a"] += arm
    ang["hand_a"] += 1.5 * arm
    ang["elbow_b"] -= arm
    ang["hand_b"] -= 1.5 * arm
    return ang


def solve_leg(rig, pose, chain, target, pelvis_x, step_len, track):
    rel = max(-1.0, min(1.0, (target[0] - (pelvis_x + track)) / step_len))
    lift = max(0.0, min(1.0, (pose_ground - target[1]) / step_lift))
    thigh = THIGH_NEUTRAL - THIGH_SWING * rel - THIGH_LIFT * lift
    default_thigh = rig.bones[chain.hip][2]
    solve_limb_ik(rig, pose, chain, target, hip_angle_offset=thigh - default_thigh, max_reach_ratio=0.97)


# Set in main once k is known; the leg solver needs them.
pose_ground = 0.0
step_lift = 0.0


def walk(rig, start_x, end_x, step_len, track, ground_y, bob):
    gait = FootLockGait(
        cycles=CYCLES, duty=DUTY, step_len=step_len, step_lift=step_lift, ground_y=ground_y,
        legs=(
            FootLockLeg("a", "toe_a", 0.0, track),
            FootLockLeg("b", "toe_b", 0.5, track),
        ),
    )
    targets = gait.targets(FRAMES + 1, start_x, end_x)
    poses = []
    travel = end_x - start_x
    for i in range(FRAMES):
        t = i / FRAMES
        g = CYCLES * t
        bx = start_x + travel * t
        by = ground_y - GROUND_LOCAL_Y * rig_scale + bob * math.cos(2.0 * math.pi * 2.0 * g)
        pose = {"pelvis": (bx, by)}
        solve_tip_chain(rig, pose, HEAD_CHAIN, upper_body_angles(rig, g))
        solve_leg(rig, pose, LEG_A, targets[i]["toe_a"], bx, step_len, track)
        solve_leg(rig, pose, LEG_B, targets[i]["toe_b"], bx, step_len, track)
        enforce_ground(pose, ground_y)
        poses.append(pose)
    return poses


rig_scale = 1.0


def render_part(session, traced, png):
    scene = svg_export.Scene(traced)
    scene.run(traced["ops"])
    svg = png.with_suffix(".svg")
    svg.write_text(scene.svg(False))
    w, h = traced["canvas"]["width"], traced["canvas"]["height"]
    subprocess.check_call(["rsvg-convert", "-w", str(w), "-h", str(h), str(svg), "-o", str(png)])
    svg.unlink()


def main():
    global pose_ground, step_lift, rig_scale
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    model = out / "model.xml"
    z = zipfile.ZipFile(PACK)
    inner = zipfile.ZipFile(z.open("items/trex.ati"))
    model.write_bytes(inner.read("model.xml"))

    parts = item_boil.load(PACK, "trex.ati")
    _, box = item_boil.render(parts, None, None)
    k = DISPLAY / (box[2] - box[0])
    rig_scale = k
    rig = CharacterRig.from_item_model(
        model, id_to_name=ID_TO_NAME, unit_name="@:trex", base_name="pelvis", scale=k,
    )
    step_len = STEP_LEN_ITEM * k
    step_lift = STEP_LIFT_ITEM * k
    track = TRACK_ITEM * k
    ground_y = FEET_Y
    pose_ground = ground_y
    bob = BOB_ITEM * k

    # One cycle to the right. The return is that cycle mirrored around the middle of
    # the path and played forward, so the pelvis travels back and the feet keep
    # stepping in the direction of travel. Reversing the frames made it moonwalk.
    right = walk(rig, 0.0, CYCLES * 2.0 * step_len / DUTY, step_len, track, ground_y, bob)
    axis = (right[0]["pelvis"][0] + right[-1]["pelvis"][0]) / 2
    back = [mirror_pose(pose, axis) for pose in right]
    frames = [(p, False) for p in right] + [(p, True) for p in back]

    # Centre the travel on the page. Rest-box centre, not the pelvis, is what looks centred.
    travel = right[-1]["pelvis"][0] - right[0]["pelvis"][0]
    box_center = (box[0] + box[2]) / 2 * k
    shift = PAGE_W / 2 - box_center - travel / 2
    shifted = []
    for pose, flip in frames:
        moved = {name: (x + shift, y) for name, (x, y) in pose.items()}
        shifted.append((moved, flip))

    xs = [x for pose, _ in shifted for x, _ in pose.values()]
    ys = [y for pose, _ in shifted for _, y in pose.values()]
    print(f"k {k:.4f} frames {len(shifted)} x {min(xs):.0f}..{max(xs):.0f} y {min(ys):.0f}..{max(ys):.0f}")
    if min(xs) < -40 or max(xs) > PAGE_W + 40 or max(ys) > PAGE_H + 20:
        raise SystemExit("trex_walk: the walk leaves the page")

    meta_parts = []
    for i, part in enumerate(parts):
        session, origin, kind = item_restyle.part_session(part, k, 100 + i, None)
        print(f"part {part['weight']}: {kind}")
        name = f"w{part['weight']}"
        render_part(session, session, out / f"{name}_still.png")
        base = boil.fills(session)[1]
        for n in range(item_restyle.COUNT):
            for attempt in range(boil.TRIES):
                traced = boil.variant(session, random.Random(1000 * (n + 1) + 10 * i + attempt))
                if boil.leaks(base, boil.fills(traced)[1]) is None:
                    break
            else:
                raise SystemExit(f"trex_walk: part {part['weight']} copy {n} leaked")
            render_part(session, traced, out / f"{name}_{n}.png")
        meta_parts.append({
            "name": name,
            "weight": part["weight"],
            "start": int(part["start_id"]),
            "end": int(part["end_id"]),
            "ox": origin[0],
            "oy": origin[1],
            "w": session["canvas"]["width"],
            "h": session["canvas"]["height"],
        })

    poses = []
    for pose, flip in shifted:
        poses.append({
            "flip": flip,
            "pts": [[NAME_TO_ID[name], round(x, 2), round(y, 2)] for name, (x, y) in pose.items()],
        })
    doc = {"k": k, "margin": item_restyle.MARGIN, "parts": meta_parts, "poses": poses}
    (out / "walk.json").write_text(json.dumps(doc))
    model.unlink()
    print("wrote", out / "walk.json")


if __name__ == "__main__":
    main()
