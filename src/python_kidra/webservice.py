"""The internal logic of the kidra web-service"""
import time
from dataclasses import dataclass
from subprocess import Popen
from collections.abc import Callable, Iterable
from typing import Optional

import cherrypy
import requests


@dataclass(frozen=True)
class Service:
    """Contains all the necessary information about a service"""

    name: str  #: Sub-domain to assign the service in the kidra to
    binary: str  #: Executable to use to start the service
    host: str  #: Host domain of the service (usually localhost)
    port: Optional[
        str
    ] = None  #: Port the service is listening to (must be unique if autostarting)
    post_subdomain: Optional[str] = None  #: Sub-domain for POST requests
    ping_subdomain: str = "_ping"  #: Sub-domain for pinging the service
    boot_timeout: Optional[
        float
    ] = 15  #: Time in seconds to wait for service to boot. Infinite if None
    autostart: bool = True  #: Whether to automatically start this service

    @property
    def api_address(self) -> str:
        """Full address for POST requests"""
        if self.port is not None:
            return f"http://{self.host}:{self.port}/{self.post_subdomain}"
        return f"https://{self.host}/{self.post_subdomain}"

    @property
    def ping_address(self) -> str:
        """Full address for ping"""
        if self.port is not None:
            return f"http://{self.host}:{self.port}/{self.ping_subdomain}"
        return f"https://{self.host}/{self.ping_subdomain}"


def start_subservice(service: Service) -> None:
    """Start the given service and wait until it is accessible"""

    print(f"Starting {service.name} on port {service.port}...")
    Popen(
        [service.binary, f"--port={service.port}"],
        stdin=None,
        stdout=None,
        stderr=None,
        close_fds=True,
        shell=False,
    )

    # try pinging the service and wait until it is up
    success = False
    start_time = time.time()
    while not success:
        if (
            service.boot_timeout is not None
            and time.time() - start_time > service.boot_timeout
        ):
            raise TimeoutError(
                f"{service.name} took more than the allowed {service.boot_timeout} seconds to become reachable"
            )

        try:
            r = requests.get(service.ping_address)
        except requests.exceptions.ConnectionError:
            time.sleep(0.1)
        else:
            success = r.status_code == 200

    print("DONE")


def get_post_request_fun(service: Service) -> Callable[[dict], dict]:
    """Create a POST request function from the given service"""

    def fun(data: dict) -> dict:
        return requests.post(service.api_address, json=data).json()

    return fun


class KidraService:
    def __init__(self, services: Iterable[Service]):
        """Create the kidra with given services, automatically starting them"""
        self.post_request_funs = dict()
        for service in services:
            if service.autostart:
                start_subservice(service)

            self.post_request_funs[service.name] = get_post_request_fun(service)

    def _cp_dispatch(self, vpath: list[str]):
        """
        Override the sub-domain handling

        This way, they can be allocated dynamically
        """
        if len(vpath) == 1:
            # if ping was requested, do not override the path
            if vpath[0] == "_ping":
                return self

            # otherwise, modify the request such that it goes to the index
            cherrypy.request.params["service"] = vpath.pop()
            return self

        return vpath

    @cherrypy.expose
    @cherrypy.tools.json_in()
    @cherrypy.tools.json_out()
    def index(self, service: str):
        """Access the given service through the kidra"""
        try:
            return self.post_request_funs[service](cherrypy.request.json)

        except KeyError:
            raise cherrypy.HTTPError(
                status=404, message=f'Service "{service}" could not be found'
            )

    @cherrypy.expose
    def _ping(self):
        """Return an empty HTTP response, for healthchecks"""
        pass
