package main

import "core:fmt"
import "core:math/rand"
import "core:os"
import "core:strings"
import "core:sync"
import "core:sys/posix"
import "core:terminal/ansi"
import "core:time"

// === GLOBALS ===

INITIAL_DENSITY :: 0.18
FRAME_TIME_MS :: 500 * time.Millisecond

running := true

// === TERMINAL ===

color_ansi :: #force_inline proc(seq: string) -> string {
	return fmt.tprintf("\x1b[%vm", seq)
}

print_ansi :: #force_inline proc(seq: string) {
	fmt.printf("\x1b[%v", seq)
}

terminal_cleanup :: proc() {
	print_ansi(ansi.DECASB_EXIT) // Exit alt mode
	print_ansi(ansi.DECTCEM_SHOW) // Show cursor
}

color_for_age :: proc(age: u16) -> string {
	switch age {
	case 0:
		return color_ansi(ansi.FG_BLACK)
	case 1 ..= 2:
		return color_ansi(ansi.FG_WHITE)
	case 3 ..= 5:
		return color_ansi(ansi.FG_CYAN)
	case 6 ..= 10:
		return color_ansi(ansi.FG_BLUE)
	case 11 ..= 20:
		return color_ansi(ansi.FG_GREEN)
	case 21 ..= 40:
		return color_ansi(ansi.FG_MAGENTA)
	case:
		return color_ansi(ansi.FG_BRIGHT_BLACK)
	}
}

// === GRID ===

Grid :: struct {
	width, height: int,
	current, next: []u16,
}

make_grid :: proc(width, height: int) -> (grid: Grid, err: os.Error) {
	// check overflow
	if height != 0 && width > max(int) / height {
		return grid, .EOVERFLOW
	}

	total := width * height

	current := make([]u16, total) or_return // the error early
	next := make([]u16, total) or_return

	grid = Grid{width, height, current, next}

	return grid, err // same deal here; err will be .None if everything succeeds.
}

grid_destroy :: proc(grid: ^Grid) {
	delete(grid.current)
	delete(grid.next)

	grid^ = {}
}

grid_randomize :: #force_inline proc(grid: ^Grid) {
	for &cell in grid.current {
		if rand.float64() < INITIAL_DENSITY {
			cell = 1
		} else {
			cell = 0
		}
	}
}

grid_index :: #force_inline proc(grid: ^Grid, x, y: int) -> int {
	return y * grid.width + x
}

grid_alive_count :: proc(grid: ^Grid) -> (alive: int) {
	for &cell in grid.current {
		if cell != 0 {
			alive += 1
		}
	}

	return alive
}

grid_neighbors_count :: proc(grid: ^Grid, x, y: int) -> (count: int) {
	for dy in -1 ..= 1 {
		for dx in -1 ..= 1 {
			if dx == 0 && dy == 0 {
				continue
			}

			nx := (x + dx + grid.width) % grid.width
			ny := (y + dy + grid.height) % grid.height

			if grid.current[grid_index(grid, nx, ny)] != 0 {
				count += 1
			}
		}
	}

	return count
}

grid_update :: proc(grid: ^Grid) {
	for y in 0 ..< grid.height {
		for x in 0 ..< grid.width {
			index := grid_index(grid, x, y)
			age := grid.current[index]
			neighbors := grid_neighbors_count(grid, x, y)

			alive := age != 0
			survives := alive && (neighbors == 2 || neighbors == 3)
			spawns := !alive && neighbors == 3

			if survives {
				grid.next[index] = age + u16(age < max(u16))
			} else {
				grid.next[index] = u16(spawns)
			}

			// switch {
			// case alive && (neighbors == 2 || neighbors == 3):
			// 	grid.next[index] = min(age + 1, max(u16))
			// case !alive && neighbors == 3:
			// 	grid.next[index] = 1
			// case:
			// 	grid.next[index] = 0
			// }
		}
	}

	tmp := grid.current
	grid.current = grid.next
	grid.next = tmp
}

grid_render :: proc(grid: ^Grid) -> string {
	out := strings.builder_make()
	strings.builder_grow(&out, grid.width * grid.height * 8)
	defer strings.builder_destroy(&out)

	strings.write_string(&out, "\x1b[H")

	for y in 0 ..< grid.height {
		for x in 0 ..< grid.width {
			age := grid.current[grid_index(grid, x, y)]

			if age == 0 {
				strings.write_byte(&out, ' ')
			} else {
				strings.write_string(&out, color_for_age(age))
				strings.write_rune(&out, '█')
			}
		}

		strings.write_byte(&out, '\n')
	}

	strings.write_string(&out, color_ansi(ansi.RESET))

	return strings.to_string(out)
}

// Handle exit signal
exit_sig :: proc "c" (sig: posix.Signal) {
	sync.atomic_store_explicit(&running, false, .Release)
}

// === MAIN ===

main :: proc() {
	posix.signal(.SIGINT, exit_sig)
	posix.signal(.SIGTERM, exit_sig)
	defer terminal_cleanup()

	width, height, ok := get_terminal_size()
	if !ok {
		fmt.eprintln("could not determine terminal size")
		os.exit(1)
	}

	if height > 0 {
		height -= 1
	}

	grid, err := make_grid(width, height)
	if err != nil {
		fmt.eprintln("could not create grid:", err)
		os.exit(1)
	}
	defer grid_destroy(&grid)

	grid_randomize(&grid)

	print_ansi(ansi.DECASB_ENTER) // Enter alt mode
	print_ansi(ansi.DECTCEM_HIDE) // Hide cursor

	for sync.atomic_load_explicit(&running, .Acquire) {
		frame := grid_render(&grid)

		os.write_string(os.stdout, frame)

		grid_update(&grid)

		time.sleep(FRAME_TIME_MS)
	}
}
