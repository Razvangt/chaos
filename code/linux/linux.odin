package linux


import "core:log"
import "../common"

main :: proc() {
	context.logger = log.create_console_logger()
	log.panic("Not Implemented", common.GAME_TITLE)
}
