# How many moving units does Godot 4 hold at 60 and 30 fps?

The most units each of four common ways of moving them kept at a steady 60 fps
and 30 fps, searched for size by size on one machine. The code is
[`benchmark/bench.gd`](benchmark/bench.gd); every size it tried, with its frame
times, is in [`benchmark/results/`](benchmark/results/).

**One machine, one Godot version, and a machine that was busy with other
work while it ran.** Read the caveats before quoting a number.

## The answer

| Setup | 60 fps: run 1 | run 2 | run 3 | 30 fps: run 1 | run 2 |
|---|---:|---:|---:|---:|---:|
| NavigationAgent3D per unit, avoidance on | 2,650 | 4,750 | 1,450 | 8,000 | 8,500 |
| NavigationAgent3D per unit, avoidance off | 1,950 | 7,000 | 3,650 | 13,500 | 14,000 |
| One path per squad of 20, a node per unit | 4,150 | 11,500 | 11,500 | 25,000 | 24,000 |
| Flow field, all units in one MultiMesh | 20,000 | 23,000 | 20,000 | 48,000 | 48,000 |

Each figure is the largest count that held; the search tried a count about
5% above it, and that one failed. Runs 1 and 2 were back to back on
2026-10-15
([run 1](benchmark/results/ceiling-2026-10-15T182141.csv),
[run 2](benchmark/results/ceiling-2026-10-15T183322.csv)); run 3 repeated the
60 fps half on 2026-10-16
([run 3](benchmark/results/ceiling-2026-10-16T052556.csv)).

Measured on: Intel Core i7-12700F (20 threads), 16 GB RAM, NVIDIA GeForce RTX
3060 Ti, Vulkan, Forward+ renderer, Godot 4.7.1-stable (official), Windows 11
(10.0.26200), a 1280 x 720 window. The first line of each CSV records this, as
Godot reports it.

## What "holds" means

At F fps the simulation steps F times a second (a 30 fps game steps 30 times
a second, so the 30 fps runs set `physics_ticks_per_second` to 30). A count
holds when, over 5 seconds measured after 3 seconds of warm-up:

- the 95th-percentile frame that ran one step is inside the frame budget
  (16.7 ms at 60 fps, 33.3 ms at 30),
- no more than 1% of steps ran in catch-up frames, where the simulation had
  fallen behind and ran two or more steps in one frame (a hitch the player
  sees), and
- the simulation kept at least 98% of its steps a second.

Vsync is off and the frame rate uncapped, so a frame that ran a step costs
what a step costs plus a draw. The whole budget goes to the units: there is
no game around them.

## What it shows

- **At 30 fps the answer repeats.** The two runs agree to within 7% for every
  setup. A NavigationAgent3D per unit holds about 8,000 to 8,500 with
  avoidance and about 14,000 without. A squad path holds about 24,000. The
  flow field holds 48,000.
- **At 60 fps the flow field repeats and the node setups do not.** The flow
  field held 20,000 to 23,000 in all three runs. The three setups with a node
  per unit moved by as much as 3.6 times between runs: avoidance agents held
  2,650, then 4,750, then 1,450. What failed them was almost always the hitch
  test, not the average. Frames of 25 to 50 ms turned up at a few percent of
  steps, at sizes where the average frame was well inside 16.7 ms. A 30 fps
  frame has room to absorb a hitch that size, so the 30 fps runs pass where
  the 60 fps runs do not. Whether those hitches come from the engine or
  from the other programs on the machine (below) is not settled by these
  runs. The lowest figure in each row is the safer one to plan with.
- **The flow field's cost grows in a straight line.** One step costs about
  0.64 ms per 1,000 units, at 16,000 units and at 48,000 alike. That loop is
  GDScript over packed arrays, so it is the number C# or a GDExtension would
  lower.
- **Past the ceiling things fall off fast.** At double its ceiling (32,000
  at 60 fps, 64,000 at 30) the flow field ran no one-step frames at all:
  every frame was a catch-up frame of 150 to 320 ms, and the simulation ran
  well short of its steps.

## Caveats

- **One machine.** A slower CPU lowers every number. These setups are bound
  by one CPU thread, not by the GPU: at every size that held, frames that only
  drew averaged under 4 ms.
- **The machine was busy.** Other jobs ran at the same time (Python
  processes, the antivirus scanner, other development tools). During run 3,
  total CPU load sampled every 10 seconds had a median of about 46% and
  reached 90%. A quiet machine would likely give higher and steadier 60 fps
  figures for the node setups. The 30 fps figures and the flow field held
  steady in spite of the load.
- **One Godot version**: 4.7.1, Forward+, Vulkan, Windows. Navigation and
  avoidance have changed between Godot 4 releases, so the agent rows are the
  ones most likely to move with a version.
- **Not like for like in behaviour.** Only the avoidance agents avoid each
  other. Squad members follow a slot behind a shared path and can clip a
  wall's corner, and flow-field units go wherever the field points. The setups
  are compared on the cost of moving units, not on how well they move.
- **No game.** No combat, targeting, animation, physics bodies or AI
  decisions; those come out of the same budget. The map is a fixed 200 x 200 m
  with eight walls, so more units also means a denser crowd.
- **Two or three runs per number**, which is enough to show which figures repeat
  and which do not, and not enough for a confidence interval.

## Run it on your machine

From the repository root, with Godot 4 on your PATH. It opens a window, since
drawing is part of what is measured, and the full search took about 10 to 12 minutes here:

```bash
godot --path . -s res://benchmark/bench.gd -- mode=ceiling
godot --path . -s res://benchmark/bench.gd -- mode=ceiling fps=60 setups=flow_multimesh
```

Results go to `benchmark/results/ceiling-<date>T<time>.csv`, with your CPU,
GPU, renderer and Godot version on the first line, one row for every size
tried, and a `# ceiling,...` summary line per setup at the end. Close what
you can first. Numbers from other hardware are what this table is missing.

The frame-time sweep from 100 to 8,000 units that came before this, which
reports average frame times rather than ceilings, is in
[`benchmark/README.md`](benchmark/README.md).

None of this ships with the addon: the Asset Library download carries only
`addons/`.
