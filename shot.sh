echo start
timeout 15 luna-send -n 1 -f luna://com.webos.service.applicationmanager/launch '{"id":"com.ha-launcher.home"}'; echo "launch rc=$?"
sleep 4
timeout 15 luna-send -n 1 -f luna://com.webos.service.applicationmanager/getForegroundAppInfo '{}'; echo "fg rc=$?"
rm -f /tmp/shot.jpg
timeout 20 luna-send -n 1 -f luna://com.webos.service.capture/executeOneShot '{"path":"/tmp/shot.jpg","method":"DISPLAY","width":960,"height":540,"format":"JPG"}'; echo "cap rc=$?"
