#!/bin/sh
# Temp: run our own server on :4010, shoot the tour against it, stop it again.
set -e
PORT=4010 nohup mix phx.server > /tmp/vn-4010.log 2>&1 &
PID=$!

code=""
i=0
while [ "$i" -lt 120 ]; do
  code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:4010/users/log-in || true)
  if [ "$code" = "200" ]; then break; fi
  i=$((i + 1))
  sleep 1
done
echo "alt server HTTP $code"
if [ "$code" != "200" ]; then
  tail -30 /tmp/vn-4010.log
  kill "$PID" 2>/dev/null || true
  exit 1
fi

cd scripts/visual
node tour.js http://localhost:4010 "ops@example.com:correct horse battery" "../../.shots/v" || true
cd ../..

kill "$PID" 2>/dev/null || true
echo done
