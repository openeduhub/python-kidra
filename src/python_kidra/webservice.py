"""The internal logic of the kidra web-service"""
import time
from collections.abc import Callable, Iterable, Iterator
from dataclasses import dataclass
from subprocess import Popen
from typing import Any, Optional, TypeVar
from pprint import pprint

from python_kidra._version import __version__

import requests
from fastapi.openapi.utils import get_openapi


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
    openapi_schema: str = (
        "openapi.json"  #: Sub-domain for getting the api of the service
    )
    boot_timeout: Optional[
        float
    ] = 600  #: Time in seconds to wait for service to boot. Infinite if None
    autostart: bool = True  #: Whether to automatically start this service

    @property
    def post_address(self) -> str:
        """Full address for POST requests"""
        if self.port is not None:
            return f"http://{self.host}:{self.port}/{self.post_subdomain}"
        return f"https://{self.host}/{self.post_subdomain}"

    @property
    def api_schema_address(self) -> str:
        """Full address for POST requests"""
        if self.port is not None:
            return f"http://{self.host}:{self.port}/{self.openapi_schema}"
        return f"https://{self.host}/{self.openapi_schema}"

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
            success = r.status_code == 200
            if not success:
                time.sleep(1)

        except requests.exceptions.ConnectionError:
            time.sleep(1)

    print("DONE")


def get_post_request_fun(service: Service) -> Callable[[dict], dict]:
    """Create a POST request function from the given service"""

    def fun(data: dict) -> dict:
        return requests.post(service.post_address, json=data).json()

    return fun


def generate_sub_services(app, services: Iterable[Service]):
    for service in services:
        if service.autostart:
            start_subservice(service)

        post_request_fun = get_post_request_fun(service)
        app.post(f"/{service.name}")(post_request_fun)


def __dictionary_leaves(dictionary: dict) -> Iterator[tuple[list[str], Any]]:
    """Iterate over all leaf-nodes of a nested dictionary"""
    for key, value in dictionary.items():
        if type(value) is dict:
            for sub_keys, sub_value in __dictionary_leaves(value):
                yield [key] + sub_keys, sub_value

        else:
            yield [key], value


T = TypeVar("T")


def __apply_nested(
    dictionary: dict[str, T | dict[str, Any]], keys: list[str], fun: Callable[[T], T]
):
    """Mutate dictionary by changing its value at the given position"""
    key = keys.pop(0)
    sub_dict = dictionary[key]
    if keys:
        __apply_nested(sub_dict, keys, fun)
        return

    dictionary[key] = fun(dictionary[key])


def custom_openapi(app, services: Iterable[Service]):
    """Create a custom OpenAPI by merging the ones from the services"""
    if app.openapi_schema:
        return app.openapi_schema

    openapi_schema = get_openapi(
        title="Kidra",
        version=__version__,
        description="A unified API for Python AI services",
        routes=app.routes,
    )

    for service in services:
        service_openapi_schema = requests.get(url=service.api_schema_address).json()

        # replace APIs with the ones from the corresponding service
        openapi_schema["paths"][f"/{service.name}"] = service_openapi_schema["paths"][
            f"/{service.post_subdomain}"
        ]

        # merge in data structures
        schemas = openapi_schema["components"]["schemas"]
        service_schemas = service_openapi_schema["components"]["schemas"]
        for key, value in service_schemas.items():
            schemas[f"{service.name}-{key}"] = value

        # rename referenced data structures in the service's path
        path = openapi_schema["paths"][f"/{service.name}"]
        for keys, value in __dictionary_leaves(path):
            if type(value) is not str:
                continue

            if "components/schemas" in value:
                __apply_nested(
                    path,
                    keys,
                    lambda x: x.replace(
                        "components/schemas/", f"components/schemas/{service.name}-"
                    ),
                )

    app.openapi_schema = openapi_schema

    return app.openapi_schema
