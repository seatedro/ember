package main

import "../engine"
import "core:os"
import game "game:."

main :: proc() {
	if engine.run(game.configure()) != .None {
		os.exit(1)
	}
}
