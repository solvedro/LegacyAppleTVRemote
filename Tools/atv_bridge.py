#!/usr/bin/env python3
"""
Apple TV 4K Bridge for iPod Touch Remote
Relays simple HTTP commands from legacy iOS devices to Apple TV 4K via pyatv.
"""

import asyncio
import os
import sys
import json
import logging
from aiohttp import web
import pyatv
from pyatv.const import Protocol

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("atv_bridge")

ATV_IP = os.environ.get("ATV_IP", "192.168.100.155")
PORT = int(os.environ.get("BRIDGE_PORT", "8088"))
CREDENTIALS_FILE = os.path.expanduser("~/.atv_credentials")

class ATVBridge:
    def __init__(self):
        self.atv = None
        self.config = None
        self.device_name = "Living Room"
        self.pairing_handler = None
        self.lock = asyncio.Lock()

    async def get_config(self):
        loop = asyncio.get_running_loop()
        devs = await pyatv.scan(loop, hosts=[ATV_IP])
        if not devs:
            raise RuntimeError(f"Apple TV not found at {ATV_IP}")
        config = devs[0]
        self.device_name = config.name
        
        # Load saved credentials if available
        if os.path.exists(CREDENTIALS_FILE):
            with open(CREDENTIALS_FILE, "r") as f:
                creds = f.read().strip()
                if creds:
                    for s in config.services:
                        if s.protocol == Protocol.Companion:
                            s.credentials = creds
                            logger.info(f"Loaded Companion credentials for {config.name}")
        return config

    async def ensure_connected(self):
        if self.atv is not None:
            return self.atv
            
        async with self.lock:
            if self.atv is not None:
                return self.atv
                
            config = await self.get_config()
            loop = asyncio.get_running_loop()
            logger.info(f"Connecting to {config.name} ({config.address})...")
            self.atv = await pyatv.connect(config, loop)
            logger.info(f"Successfully connected to {config.name}!")
            return self.atv

    def reset_connection(self):
        if self.atv:
            try:
                self.atv.close()
            except Exception:
                pass
            self.atv = None

bridge = ATVBridge()

async def handle_status(request):
    is_connected = bridge.atv is not None
    is_paired = os.path.exists(CREDENTIALS_FILE) and os.path.getsize(CREDENTIALS_FILE) > 0
    return web.json_response({
        "status": "ok",
        "device": bridge.device_name,
        "target_ip": ATV_IP,
        "connected": is_connected,
        "paired": is_paired
    })

async def handle_press(request):
    key = request.query.get("key", "").lower().strip()
    if not key:
        return web.json_response({"error": "missing key param"}, status=400)

    try:
        atv = await bridge.ensure_connected()
        rc = atv.remote_control
        
        key_map = {
            "up": rc.up,
            "down": rc.down,
            "left": rc.left,
            "right": rc.right,
            "select": rc.select,
            "menu": rc.menu,
            "back": rc.menu,
            "home": rc.top_menu,
            "top_menu": rc.top_menu,
            "control_center": rc.control_center,
            "play": rc.play,
            "pause": rc.pause,
            "play_pause": rc.play_pause,
            "next": rc.next,
            "previous": rc.previous,
            "volume_up": rc.volume_up,
            "volume_down": rc.volume_down,
            "screensaver": rc.screensaver,
            "power": rc.play_pause,
            "wake": rc.wakeup,
            "sleep": rc.suspend
        }
        
        action = key_map.get(key)
        if not action:
            return web.json_response({"error": f"unknown key: {key}"}, status=400)
            
        await action()
        logger.info(f"Pressed key: {key}")
        return web.json_response({"success": True, "key": key})
    except Exception as e:
        logger.error(f"Failed to press key {key}: {e}")
        bridge.reset_connection()
        return web.json_response({"error": str(e)}, status=500)

async def handle_now_playing(request):
    try:
        atv = await bridge.ensure_connected()
        metadata = atv.metadata
        playing = await metadata.playing()
        
        state_str = str(playing.device_state).split(".")[-1].lower()
        media_type = str(playing.media_type).split(".")[-1].lower()
        
        info = {
            "title": playing.title or "",
            "artist": playing.artist or "",
            "album": playing.album or "",
            "state": state_str,
            "media_type": media_type,
            "position": playing.position or 0,
            "total_time": playing.total_time or 0
        }
        return web.json_response(info)
    except Exception as e:
        return web.json_response({"state": "idle", "error": str(e)})

async def handle_pair_start(request):
    try:
        loop = asyncio.get_running_loop()
        devs = await pyatv.scan(loop, hosts=[ATV_IP])
        if not devs:
            return web.json_response({"error": "Apple TV not found"}, status=404)
        atv_cfg = devs[0]
        
        if bridge.pairing_handler:
            try:
                await bridge.pairing_handler.close()
            except Exception:
                pass
            bridge.pairing_handler = None
            
        handler = await pyatv.pair(atv_cfg, Protocol.Companion, loop)
        await handler.begin()
        bridge.pairing_handler = handler
        logger.info("[*] Pairing initiated! 4-digit PIN is displayed on Apple TV screen.")
        return web.json_response({
            "success": True,
            "message": "PIN is displayed on your TV screen. Submit with /pair/submit?pin=XXXX"
        })
    except Exception as e:
        logger.error(f"Pair start failed: {e}")
        return web.json_response({"error": str(e)}, status=500)

async def handle_pair_submit(request):
    pin = request.query.get("pin", "").strip()
    if not pin or len(pin) not in (4, 6):
        return web.json_response({"error": "Please provide 4 or 6-digit PIN: ?pin=1234"}, status=400)
        
    handler = bridge.pairing_handler
    if not handler:
        return web.json_response({"error": "No active pairing session. Call /pair/start first."}, status=400)
        
    try:
        handler.pin(int(pin))
        await handler.finish()
        if handler.has_paired:
            creds = handler.service.credentials
            with open(CREDENTIALS_FILE, "w") as f:
                f.write(creds)
            logger.info(f"[+] Paired successfully! Credentials saved: {creds}")
            await handler.close()
            bridge.pairing_handler = None
            bridge.reset_connection()
            return web.json_response({
                "success": True,
                "message": "Pairing completed and saved!",
                "credentials": creds
            })
        else:
            return web.json_response({"error": "Pairing failed. Incorrect PIN."}, status=400)
    except Exception as e:
        logger.error(f"Pair submit failed: {e}")
        return web.json_response({"error": str(e)}, status=500)

async def handle_apps(request):
    try:
        atv = await bridge.ensure_connected()
        apps = await atv.apps.app_list()
        res = {a.identifier: a.name for a in apps}
        return web.json_response(res)
    except Exception as e:
        logger.error(f"Failed to fetch apps: {e}")
        return web.json_response({"error": str(e)}, status=500)

async def handle_launch(request):
    bundle_id = request.query.get("bundle_id") or request.query.get("app")
    if not bundle_id:
        return web.json_response({"error": "missing bundle_id"}, status=400)
    try:
        atv = await bridge.ensure_connected()
        await atv.apps.launch_app(bundle_id)
        logger.info(f"Launched app on Apple TV: {bundle_id}")
        return web.json_response({"success": True, "launched": bundle_id})
    except Exception as e:
        logger.error(f"Failed to launch app {bundle_id}: {e}")
        return web.json_response({"error": str(e)}, status=500)

async def handle_credentials(request):
    if os.path.exists(CREDENTIALS_FILE):
        try:
            with open(CREDENTIALS_FILE, "r") as f:
                creds = f.read().strip()
                if creds:
                    return web.json_response({"credentials": creds})
        except Exception as e:
            logger.error(f"Failed to read credentials file: {e}")
    return web.json_response({"credentials": None})

def create_app():
    app = web.Application()
    app.router.add_get("/", handle_status)
    app.router.add_get("/status", handle_status)
    app.router.add_get("/press", handle_press)
    app.router.add_get("/nowplaying", handle_now_playing)
    app.router.add_get("/pair/start", handle_pair_start)
    app.router.add_get("/pair/submit", handle_pair_submit)
    app.router.add_get("/credentials", handle_credentials)
    app.router.add_get("/apps", handle_apps)
    app.router.add_get("/launch", handle_launch)
    return app

if __name__ == "__main__":
    app = create_app()
    logger.info(f"Starting Apple TV 4K Bridge on port {PORT} for {ATV_IP}...")
    web.run_app(app, host="0.0.0.0", port=PORT)
