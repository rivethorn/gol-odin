#+build darwin
package main

import "core:sys/darwin"
import "core:sys/posix"

Winsize :: struct {
	row, col: u16,
}

get_terminal_size :: proc() -> (col, row: int, ok: bool) {
	ws: Winsize

	// syscall to get terminal size
	if darwin.syscall_ioctl(posix.STDOUT_FILENO, darwin.TIOCGWINSZ, &ws) == 0 && ws.col > 0 {
		row = int(ws.row)
		col = int(ws.col)
		ok  = true
	}

	return col, row, ok
}
