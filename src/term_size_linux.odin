#+build linux
package main

import "core:sys/linux"
import "core:sys/posix"

Winsize :: struct {
	row, col: u16,
}

get_terminal_size :: proc() -> (col, row: int, ok: bool) {
	ws: Winsize

	// syscall to get terminal size
	if linux.ioctl(posix.STDOUT_FILENO, linux.TIOCGWINSZ, uintptr(&ws)) == 0 && ws.col > 0 {
		row = int(ws.row)
		col = int(ws.col)
		ok = true
	}

	return col, row, ok
}

