package plataform

import "core:log"
import "core:math"

APP_NAME: cstring = "SDL APP"
APP_VERSION: cstring = "1.0"
APP_IDENTIFIER: cstring = "com.chaos.dev"


when ODIN_OS == .Windows {
	import "platform/windows"

	// init Start engine and set up based on plataform
	main :: proc() {
		context.logger = log.create_console_logger()
		log.info("Start of Windows Chaos ")
		windows.main_windows()
		log.info("End of Windows Chaos ")
	}
} else when ODIN_OS == .Linux {
	import "platform/linux"

	// init Start engine and set up based on plataform
	main :: proc() {
		context.logger = log.create_console_logger()
		log.info("Start of  Linux Chaos ")
		chaos.main_linux()
		log.info("End of Linux Chaos ")
	}

} else {
	main :: proc() {
		context.logger = log.create_console_logger()
		log.info("Platform not supported")
	}
}



