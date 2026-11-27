import argparse
from functools import partial

import uvicorn
from fastapi import FastAPI

from python_kidra.kidra import Service, generate_sub_services, custom_openapi
from python_kidra._version import __version__


app = FastAPI(openapi_url="/v3/api-docs")


class Ports:
    """Generator of unique ports, starting at a given value."""

    def __init__(self, start: int):
        self.current_int = start
        self.current = str(start)

    def __next__(self) -> str:
        self.current_int += 1
        self.current = str(self.current_int)

        return self.current


ports = Ports(1986)

# the collection of all services to be collected in the kidra
SERVICES: dict[str, Service] = {
    "text-statistics": Service(
        name="text-statistics",
        binary="text-statistics",
        host="localhost",
        port=next(ports),
        post_subdomain="analyze-text",
    ),
    "topic-statistics": Service(
        name="topic-statistics",
        binary="topic-statistics",
        host="localhost",
        port=next(ports),
        post_subdomain="counts",
    ),
    "update-data": Service(
        name="update-data",
        binary="",
        host="localhost",
        port=ports.current,
        post_subdomain="update-data",
        autostart=False,  # already started above
    ),
    "its-jointprobability": Service(
        name="bayesian-predictions",
        binary="its-jointprobability",
        host="localhost",
        port=next(ports),
        post_subdomain="predict",
        autostart=True,
    ),
    "topic-assistant-keywords": Service(
        name="topic-assistant-keywords",
        binary="wlo-topic-assistant",
        host="localhost",
        port=next(ports),
        post_subdomain="topics_flat",
        autostart=True,
        boot_timeout=None,
    ),
    "topic-assistant-embeddings": Service(
        name="topic-assistant-embeddings",
        binary="",
        host="localhost",
        port=ports.current,
        post_subdomain="topics2_flat",
        autostart=False,  # already started above
    ),
}


def main():
    # define CLI arguments
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--port", action="store", default=8080, help="Port to listen on", type=int
    )
    parser.add_argument(
        "--host", action="store", default="0.0.0.0", help="Hosts to listen to", type=str
    )
    parser.add_argument(
        "--username",
        action="store",
        default=None,
        help="The username to use when running a data update and authenticating at the source.",
        type=str,
    )
    parser.add_argument(
        "--password",
        action="store",
        default=None,
        help="The password to use when running a data update and authenticating at the source.",
        type=str,
    )
    parser.add_argument(
        "--data-dir",
        action="store",
        default="./.cache",
        help="The directory in which the data shall be stored. Creates directories if necessary.",
    )
    parser.add_argument(
        "--version",
        action="version",
        version="%(prog)s {version}".format(version=__version__),
    )

    # read passed CLI arguments
    args = parser.parse_args()

    # pass additional arguments onto services
    SERVICES["topic-statistics"].additional_args = {
        "username": args.username,
        "password": args.password,
        "data-dir": args.data_dir,
    }

    # add all of the defined services
    generate_sub_services(app, SERVICES.values())

    # add a ping function
    @app.get("/_ping")
    def _ping():
        pass

    # override the openapi by merging the ones of the sub-services
    app.openapi = partial(custom_openapi, app=app, services=SERVICES.values())

    # start the web service
    uvicorn.run(
        app,
        host=args.host,
        port=args.port,
        reload=False,
    )


if __name__ == "__main__":
    main()
