import nesper/esp/esp_system

type
  SimulationState* = enum
    Running, Paused

  Simulation* = object
    width*: int
    height*: int
    cells*: seq[uint8]
    scratch: seq[uint8]
    generation*: uint64
    labels*: seq[uint16]
    label_stack: seq[tuple[x, y: int]]

proc new_simulation*(width, height: int): Simulation =
  let size = width * height
  result = Simulation(
    width: width,
    height: height,
    cells: new_seq[uint8](size),
    scratch: new_seq[uint8](size),
    generation: 0,
    labels: new_seq[uint16](size),
    label_stack: new_seq_of_cap[tuple[x, y: int]](256)
  )

proc get*(sim: Simulation, x, y: int): uint8 {.inline.} =
  sim.cells[y * sim.width + x]

proc label*(sim: Simulation, x, y: int): uint16 {.inline.} =
  sim.labels[y * sim.width + x]

proc set*(sim: var Simulation, x, y: int, value: uint8) {.inline.} =
  if x >= 0 and x < sim.width and y >= 0 and y < sim.height:
    sim.cells[y * sim.width + x] = value

proc clear*(sim: var Simulation) =
  for i in 0 ..< sim.cells.len:
    sim.cells[i] = 0
  sim.generation = 0

proc step*(sim: var Simulation) =
  let w = sim.width
  let h = sim.height

  for y in 0 ..< h:
    let y_above = if y == 0: h - 1 else: y - 1
    let y_below = if y == h - 1: 0 else: y + 1
    let row_above = y_above * w
    let row_curr = y * w
    let row_below = y_below * w

    for x in 0 ..< w:
      let x_left = if x == 0: w - 1 else: x - 1
      let x_right = if x == w - 1: 0 else: x + 1

      let neighbors = sim.cells[row_above + x_left].int +
                       sim.cells[row_above + x].int +
                       sim.cells[row_above + x_right].int +
                       sim.cells[row_curr + x_left].int +
                       sim.cells[row_curr + x_right].int +
                       sim.cells[row_below + x_left].int +
                       sim.cells[row_below + x].int +
                       sim.cells[row_below + x_right].int

      let alive = sim.cells[row_curr + x]
      sim.scratch[row_curr + x] = if (alive == 1 and (neighbors == 2 or neighbors == 3)) or
                                     (alive == 0 and neighbors == 3): 1'u8
                                  else: 0'u8

  swap(sim.cells, sim.scratch)
  sim.generation += 1

proc randomize*(sim: var Simulation) =
  let seed = esp_random().uint64
  var rng = seed

  for i in 0 ..< sim.cells.len:
    rng = rng * 6364136223846793005'u64 + 1442695040888963407'u64
    sim.cells[i] = if ((rng shr 33) and 3) == 0: 1'u8 else: 0'u8

  sim.generation = 0

proc compute_labels*(sim: var Simulation) =
  let w = sim.width
  let h = sim.height

  for i in 0 ..< sim.labels.len:
    sim.labels[i] = 0

  var current_label: uint16 = 0

  const deltas = [(-1, 0), (1, 0), (0, -1), (0, 1)]

  for start_y in 0 ..< h:
    for start_x in 0 ..< w:
      let idx = start_y * w + start_x
      if sim.cells[idx] == 0 or sim.labels[idx] != 0:
        continue

      current_label = current_label + 1
      sim.label_stack.set_len(0)
      sim.label_stack.add((start_x, start_y))
      sim.labels[idx] = current_label

      while sim.label_stack.len > 0:
        let (cx, cy) = sim.label_stack.pop()

        for (dx, dy) in deltas:
          let nx = cx + dx
          let ny = cy + dy
          if nx >= 0 and nx < w and ny >= 0 and ny < h:
            let ni = ny * w + nx
            if sim.cells[ni] != 0 and sim.labels[ni] == 0:
              sim.labels[ni] = current_label
              sim.label_stack.add((nx, ny))
