# Package

version     = "0.1.1"
author      = "Termer"
description = "Asychronous TwineMedia API client library for Nim"
license     = "MIT"

installFiles = @["src/tm_client.nim"]

# Dependencies

requires "nim >= 1.4.6"

task test, "Run the tm_client tester":
  exec "nim c --run --hints:off tests/config"