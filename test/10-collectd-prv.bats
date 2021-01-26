#!/usr/bin/env bats

MSG='1234567890abcdefghijklmnopqrstuvwxyz 123'

@test "set long hostname" {
    run sh -c "echo \"$MSG\" | collectd-prv --hostname=t123456789012345678901234abcddefg"
    cat << EOF
--- output
$output
--- output
EOF

    [ "$status" -eq 1 ]
}

@test "set plugin/type" {
    run sh -c "echo \"$MSG\" | collectd-prv --service=plugin1234567890/type1234567890 --hostname=test | sed 's/time=[0-9]* //'"
    cat << EOF
--- output
$output
--- output
EOF

    [ "$status" -eq 0 ]

    result="PUTNOTIF host=test severity=okay plugin=plugin1234567890 type=type1234567890 message=\"$MSG\""

    cat << EOF
--- expected
$result
--- expected
EOF
    [ "$output" = "$result" ]
}

@test "invalid plugin/type" {
    run sh -c "echo \"$MSG\" | collectd-prv --service=plugin1234567890"
    cat << EOF
--- output
$output
--- output
EOF

    [ "$status" -eq 1 ]
}

@test "invalid plugintype: size limits" {
    run sh -c "echo \"$MSG\" | collectd-prv --service=plugin1234567890aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/foo"
    cat << EOF
--- output
$output
--- output
EOF

    [ "$status" -eq 1 ]

    run sh -c "echo \"$MSG\" | collectd-prv --service=foo/type1234567890aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    cat << EOF
--- output
$output
--- output
EOF

    [ "$status" -eq 1 ]
}

@test "escape quotes" {
    run sh -c "echo '\"\"\"\"\"' | collectd-prv --hostname=test | sed 's/time=[0-9]* //'"
    cat << EOF
--- output
$output
--- output
EOF

    [ "$status" -eq 0 ]

    result='PUTNOTIF host=test severity=okay plugin=stdout type=prv message="\"\"\"\"\""'

    cat << EOF
--- expected
$result
--- expected
EOF
    [ "$output" = "$result" ]
}

@test "escaped backslashes" {
    run sh -c "echo '"\"\\"\"\"\\""' | collectd-prv --hostname=test | sed 's/time=[0-9]* //'"
    result='PUTNOTIF host=test severity=okay plugin=stdout type=prv message="\"\\\"\"\\"'
    cat << EOF
--- output
$output
--- output
EOF

    [ "$status" -eq 0 ]
    [ "$output" = "$result" ]
}

@test "trailing backslash" {
    run sh -c "echo 'abc\\' | collectd-prv --hostname=test | sed 's/time=[0-9]* //'"
    cat << EOF
--- output
$output
--- output
EOF

    [ "$status" -eq 0 ]

    result='PUTNOTIF host=test severity=okay plugin=stdout type=prv message="abc\\"'

    cat << EOF
--- expected
$result
--- expected
EOF
    [ "$output" = "$result" ]
}

@test "NUL prefaced message" {
    run sh -c "/bin/echo -e '\x00test' | collectd-prv --hostname=test"
    cat << EOF
--- output
$output
--- output
EOF

    [ "$status" -eq 0 ]

    result=''

    cat << EOF
--- expected
$result
--- expected
EOF
    [ "$output" = "$result" ]
}

@test "discard limit" {
    run sh -c "yes \"$MSG\" | head -10 | collectd-prv --limit=3 --window=10 --hostname=test | sed 's/time=[0-9]* //'"
    cat << EOF
--- output
$output
--- output
EOF

    [ "$status" -eq 0 ]

    result="PUTNOTIF host=test severity=okay plugin=stdout type=prv message=\"$MSG\"
PUTNOTIF host=test severity=okay plugin=stdout type=prv message=\"$MSG\"
PUTNOTIF host=test severity=okay plugin=stdout type=prv message=\"$MSG\""

    cat << EOF
--- expected
$result
--- expected
EOF
    [ "$output" = "$result" ]
}

@test "long line: message is fragmented" {
    run sh -c "yes \"$MSG\" | head -10 | collectd-prv --limit=15 --window=10 --max-event-length=3 --hostname=test | sed 's/time=[0-9]* //'"
    cat << EOF
--- output
$output
--- output
EOF

    [ "$status" -eq 0 ]

    result="PUTNOTIF host=test severity=okay plugin=stdout type=prv message=\"@1:1:14@123\"
PUTNOTIF host=test severity=okay plugin=stdout type=prv message=\"@1:2:14@456\"
PUTNOTIF host=test severity=okay plugin=stdout type=prv message=\"@1:3:14@789\"
PUTNOTIF host=test severity=okay plugin=stdout type=prv message=\"@1:4:14@0ab\"
PUTNOTIF host=test severity=okay plugin=stdout type=prv message=\"@1:5:14@cde\"
PUTNOTIF host=test severity=okay plugin=stdout type=prv message=\"@1:6:14@fgh\"
PUTNOTIF host=test severity=okay plugin=stdout type=prv message=\"@1:7:14@ijk\"
PUTNOTIF host=test severity=okay plugin=stdout type=prv message=\"@1:8:14@lmn\"
PUTNOTIF host=test severity=okay plugin=stdout type=prv message=\"@1:9:14@opq\"
PUTNOTIF host=test severity=okay plugin=stdout type=prv message=\"@1:10:14@rst\"
PUTNOTIF host=test severity=okay plugin=stdout type=prv message=\"@1:11:14@uvw\"
PUTNOTIF host=test severity=okay plugin=stdout type=prv message=\"@1:12:14@xyz\"
PUTNOTIF host=test severity=okay plugin=stdout type=prv message=\"@1:13:14@ 12\"
PUTNOTIF host=test severity=okay plugin=stdout type=prv message=\"@1:14:14@3\""

    cat << EOF
--- expected
$result
--- expected
EOF
    [ "$output" = "$result" ]
}

@test "long line: fragments exceed discard limit" {
    run sh -c "yes \"$MSG\" | head -10 | collectd-prv --limit=3 --window=10 --max-event-length=3 --hostname=test | sed 's/time=[0-9]* //'"
    cat << EOF
--- output
$output
--- output
EOF

    [ "$status" -eq 0 ]

    result=""

    cat << EOF
--- expected
$result
--- expected
EOF
    [ "$output" = "$result" ]
}

@test "fragment: exact length" {
    run sh -c "echo \"$MSG\" | collectd-prv --max-event-length=${#MSG} --hostname=test | sed 's/time=[0-9]* //'"
    cat << EOF
--- output
$output
--- output
EOF

    [ "$status" -eq 0 ]

    result="PUTNOTIF host=test severity=okay plugin=stdout type=prv message=\"$MSG\""

    cat << EOF
--- expected
$result
--- expected
EOF
    [ "$output" = "$result" ]
}

@test "fragment: length off by 1" {
    MLEN=$((${#MSG} - 1))
    run sh -c "echo \"$MSG\" | collectd-prv --max-event-length=${MLEN} --hostname=test | sed 's/time=[0-9]* //'"
    cat << EOF
--- output
$output
--- output
EOF

    [ "$status" -eq 0 ]

    result="PUTNOTIF host=test severity=okay plugin=stdout type=prv message=\"@1:1:2@${MSG:0:$MLEN}\"
PUTNOTIF host=test severity=okay plugin=stdout type=prv message=\"@1:2:2@${MSG:$MLEN}\""

    cat << EOF
--- expected
$result
--- expected
EOF
    [ "$output" = "$result" ]
}

@test "fragment: length is multiple of fragment length" {
    MSG2="123456789"
    run sh -c "echo \"${MSG2}\" | collectd-prv --max-event-length=3 --hostname=test | sed 's/time=[0-9]* //'"
    cat << EOF
--- output
$output
--- output
EOF

    [ "$status" -eq 0 ]

    result="PUTNOTIF host=test severity=okay plugin=stdout type=prv message=\"@1:1:3@123\"
PUTNOTIF host=test severity=okay plugin=stdout type=prv message=\"@1:2:3@456\"
PUTNOTIF host=test severity=okay plugin=stdout type=prv message=\"@1:3:3@789\""

    cat << EOF
--- expected
$result
--- expected
EOF
    [ "$output" = "$result" ]
}

@test "fragment: id rollover" {
    run sh -c "yes 'ab' | collectd-prv --max-event-length=1 --hostname=test | sed 's/time=[0-9]* //' | head -200 | tail -4"
    cat << EOF
--- output
$output
--- output
EOF

    [ "$status" -eq 0 ]

    result='PUTNOTIF host=test severity=okay plugin=stdout type=prv message="@99:1:2@a"
PUTNOTIF host=test severity=okay plugin=stdout type=prv message="@99:2:2@b"
PUTNOTIF host=test severity=okay plugin=stdout type=prv message="@1:1:2@a"
PUTNOTIF host=test severity=okay plugin=stdout type=prv message="@1:2:2@b"'

    cat << EOF
--- expected
$result
--- expected
EOF
    [ "$output" = "$result" ]
}

@test "window: number of messages per window" {
    run sh -c "(timeout -s 9 3 yes \"$MSG\" | collectd-prv --limit=1 --window=1 --hostname=test) 2>&1 | grep -cv Killed"
    cat << EOF
--- output
$output
--- output
EOF

    # timeout quirk: elapsed = 4 seconds
    result="4"

    cat << EOF
--- expected
$result
--- expected
EOF
    [ "$output" -eq "$result" ]
}
