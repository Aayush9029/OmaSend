"""Local multicast discovery test. Run alongside the isolated Windows app with discovery enabled."""
import argparse
import socket
import time
from zeroconf import ServiceBrowser, ServiceInfo, Zeroconf
from interop import Peer, eventually

p = argparse.ArgumentParser(); p.add_argument("--port", type=int, default=53320); args = p.parse_args()
peer = Peer("Python mDNS test")
found = []
class Listener:
    def add_service(self, zc, kind, name):
        info = zc.get_service_info(kind, name)
        if info and info.port == args.port:
            assert info.properties.get(b"v") == b"1" and info.properties.get(b"id")
            found.append(info)
    def update_service(self, *args): self.add_service(*args)
    def remove_service(self, *args): pass

with Zeroconf() as zc:
    browser = ServiceBrowser(zc, "_omasend._tcp.local.", Listener())
    info = ServiceInfo("_omasend._tcp.local.", "PythonOmaSendTest._omasend._tcp.local.", addresses=[socket.inet_aton("127.0.0.1")], port=peer.port, properties={"v":"1", "id":"python-mdns", "name":"Python mDNS test"}, server="python-omasend-test.local.")
    zc.register_service(info)
    eventually(lambda: bool(found) and peer.hellos > 0, 30)
    print("PASS actual Windows multicast advertisement and Python service discovery followed by encrypted hello")
    zc.unregister_service(info)
    browser.cancel()
