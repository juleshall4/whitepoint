#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p .build
xcrun swiftc Sources/Schedule.swift Tests/main.swift -o .build/schedule-tests
.build/schedule-tests
